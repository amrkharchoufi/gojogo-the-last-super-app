/*
 * The console.
 *
 * No framework and no build step, deliberately: this is a stopgap that should be
 * deletable the day the real GojoAdmin exists, and a toolchain would make it a
 * thing somebody has to maintain in the meantime.
 *
 * Two rules it holds to throughout, both inherited from the backend's posture:
 *
 *   1. **The server decides, the console renders.** It never computes whether an
 *      application may be approved, what a stake should be, or which documents
 *      are missing — every one of those is a field the API already answers
 *      (`submitBlocker`, `missingDocuments`, `canSubmit`, `stake`). A second
 *      copy of a rule is a rule that will disagree.
 *
 *   2. **Consequential decisions are confirmed, and say what they will do.**
 *      Approve provisions a real driver or restaurant into a vertical; suspend
 *      takes a live merchant out of the catalog; remove is the door that only
 *      opens outward. Each names its consequence before it runs.
 */

const $ = (sel, root = document) => root.querySelector(sel);
const el = (tag, props = {}, ...kids) => {
  const node = Object.assign(document.createElement(tag), props);
  for (const kid of kids.flat()) {
    if (kid == null || kid === false) continue;
    node.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
  }
  return node;
};

// ── Transport ───────────────────────────────────────────────────────────────

async function api(path, { method = 'GET', body } = {}) {
  const res = await fetch('/api' + path, {
    method,
    headers: body ? { 'content-type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined
  });
  const text = await res.text();
  let payload = null;
  try { payload = text ? JSON.parse(text) : null; } catch { payload = { message: text }; }
  if (!res.ok) {
    // The server's own words. Its refusals are written for a human to read —
    // "The owner hasn't passed their ID check yet" is more useful than anything
    // this file could invent.
    throw new Error(payload?.message || `${res.status} ${res.statusText}`);
  }
  return payload;
}

// ── Chrome ──────────────────────────────────────────────────────────────────

function toast(message, bad = false) {
  const node = el('div', { className: `toast${bad ? ' toast-bad' : ''}` }, message);
  $('#toasts').append(node);
  setTimeout(() => node.remove(), bad ? 8000 : 4000);
}

/** Asks before anything consequential. Resolves to a note, or null on cancel. */
function confirmAction({ title, detail, confirmLabel, danger, noteLabel, noteRequired }) {
  return new Promise(resolve => {
    const note = el('textarea', { placeholder: noteRequired ? 'Required' : 'Optional' });
    const go = el('button', {
      className: `btn ${danger ? 'btn-danger' : 'btn-primary'}`, textContent: confirmLabel
    });
    const cancel = el('button', { className: 'btn', textContent: 'Cancel' });
    const scrim = el('div', { className: 'scrim' },
      el('div', { className: 'modal', role: 'dialog', 'aria-modal': 'true' },
        el('h2', {}, title),
        el('p', {}, detail),
        noteLabel ? el('label', { className: 'field' },
          el('span', {}, noteLabel), note) : null,
        el('div', { className: 'actions' }, go, cancel)));

    const close = value => { scrim.remove(); document.removeEventListener('keydown', onKey); resolve(value); };
    const onKey = e => { if (e.key === 'Escape') close(null); };
    go.onclick = () => {
      if (noteRequired && !note.value.trim()) { note.focus(); return; }
      close(note.value.trim());
    };
    cancel.onclick = () => close(null);
    scrim.onclick = e => { if (e.target === scrim) close(null); };
    document.addEventListener('keydown', onKey);
    $('#modal-root').append(scrim);
    (noteLabel ? note : go).focus();
  });
}

const badgeClass = status => ({
  SUBMITTED: 'badge-pending', DRAFT: 'badge', APPROVED: 'badge-ok',
  REJECTED: 'badge-bad', SUSPENDED: 'badge-off',
  OPEN: 'badge-pending', ACTIONED: 'badge-ok', DISMISSED: 'badge'
}[status] || 'badge');

const badge = (text, cls) => el('span', { className: `badge ${cls || ''}` }, text);
const money = (minor, ccy = 'USD') => `${ccy} ${(minor / 100).toFixed(2)}`;
const when = iso => iso ? new Date(iso).toLocaleString() : '—';

function skeleton(rows = 4) {
  return el('div', { className: 'card' },
    ...Array.from({ length: rows }, () =>
      el('div', { className: 'skeleton', style: 'margin:10px 0' })));
}

function empty(title, body) {
  return el('div', { className: 'empty' }, el('h3', {}, title), el('p', {}, body));
}

// ── View: partner applications ──────────────────────────────────────────────

const PARTNER_STATUSES = ['SUBMITTED', 'DRAFT', 'APPROVED', 'SUSPENDED', 'REJECTED'];
const state = { partnerStatus: 'SUBMITTED', partnerKind: '', selected: null, rows: [] };

async function viewPartners(main) {
  main.replaceChildren(
    el('div', { className: 'main-head' },
      el('div', {},
        el('h1', {}, 'Applications'),
        el('p', {}, 'Every economic player enters through here — a restaurant, a driver, '
          + 'a courier. Approving one provisions it into its vertical for real.'))),
    filterBar(),
    el('div', { id: 'partner-body' }, skeleton()));
  await loadPartners();
}

function filterBar() {
  const bar = el('div', { className: 'filters' });
  for (const status of PARTNER_STATUSES) {
    const chip = el('button', { className: 'chip', textContent: status.toLowerCase() });
    chip.setAttribute('aria-pressed', String(state.partnerStatus === status));
    chip.onclick = () => { state.partnerStatus = status; state.selected = null; refreshPartners(); };
    bar.append(chip);
  }
  bar.append(el('span', { style: 'width:var(--md)' }));
  for (const kind of ['', 'RESTAURANT', 'DRIVER', 'COURIER']) {
    const chip = el('button', { className: 'chip', textContent: kind ? kind.toLowerCase() : 'all kinds' });
    chip.setAttribute('aria-pressed', String(state.partnerKind === kind));
    chip.onclick = () => { state.partnerKind = kind; state.selected = null; refreshPartners(); };
    bar.append(chip);
  }
  return bar;
}

async function refreshPartners() {
  const main = $('#main');
  main.replaceChildren(main.firstChild, filterBar(), el('div', { id: 'partner-body' }, skeleton()));
  await loadPartners();
}

async function loadPartners() {
  const params = new URLSearchParams({ status: state.partnerStatus, limit: '100' });
  if (state.partnerKind) params.set('kind', state.partnerKind);
  try {
    state.rows = await api(`/v1/partner/admin/applications?${params}`);
  } catch (err) {
    $('#partner-body').replaceChildren(empty('Could not load the queue', err.message));
    return;
  }
  $('#count-partners').textContent = state.partnerStatus === 'SUBMITTED' ? state.rows.length || '' : '';
  renderPartnerBody();
}

function renderPartnerBody() {
  const body = $('#partner-body');
  if (!body) return;
  if (!state.rows.length) {
    body.replaceChildren(empty('Nothing here',
      `No ${state.partnerStatus.toLowerCase()} applications${state.partnerKind ? ` of kind ${state.partnerKind}` : ''}.`));
    return;
  }
  const rows = el('tbody');
  for (const row of state.rows) {
    const a = row.account;
    const tr = el('tr', {},
      el('td', {}, el('div', {}, a.businessName),
        el('div', { className: 'mono muted' }, a.id.slice(0, 8))),
      el('td', {}, a.kind.toLowerCase()),
      el('td', {}, badge(a.status.toLowerCase(), badgeClass(a.status))),
      el('td', { className: 'subtle' }, [a.city, a.country].filter(Boolean).join(', ') || '—'),
      el('td', { className: 'mono muted' }, when(a.submittedAt || a.createdAt)));
    tr.setAttribute('aria-selected', String(state.selected === a.id));
    tr.onclick = () => { state.selected = a.id; renderPartnerBody(); };
    rows.append(tr);
  }
  const table = el('div', { className: 'card', style: 'padding:0;overflow:hidden' },
    el('table', {},
      el('thead', {}, el('tr', {},
        ...['Applicant', 'Kind', 'Status', 'Where', 'Filed'].map(h => el('th', {}, h)))),
      rows));

  const chosen = state.rows.find(r => r.account.id === state.selected);
  body.replaceChildren(el('div', { className: 'split' }, table,
    el('div', { className: 'detail' },
      chosen ? partnerDetail(chosen) : el('div', { className: 'card-soft' },
        el('p', { className: 'subtle' }, 'Select an application to review it.')))));
}

function partnerDetail(row) {
  const a = row.account;
  const card = el('div', { className: 'card' });

  card.append(
    el('h2', {}, a.businessName),
    el('div', { className: 'mono muted', style: 'margin-bottom:var(--md)' }, a.id));

  // Why it can or cannot be approved — the server's answer, not ours.
  const gate = a.status === 'SUBMITTED'
    ? (a.submitBlocker
        ? el('div', { className: 'blocker' }, `Blocked: ${a.submitBlocker}`)
        : el('div', { className: 'blocker blocker-ok' }, 'Everything the server checks is satisfied.'))
    : null;
  if (gate) card.append(gate);

  card.append(el('div', { className: 'section-label' }, 'Applicant'));
  card.append(el('dl', { className: 'kv' },
    el('dt', {}, 'kind'), el('dd', {}, a.kind),
    el('dt', {}, 'status'), el('dd', {}, badge(a.status.toLowerCase(), badgeClass(a.status))),
    el('dt', {}, 'contact'), el('dd', {}, [a.contactName, a.contactPhone].filter(Boolean).join(' · ') || '—'),
    el('dt', {}, 'address'), el('dd', {}, [a.addressLine, a.city, a.country].filter(Boolean).join(', ') || '—'),
    el('dt', {}, 'identity'), el('dd', {},
      a.identityRequired
        ? badge(a.identityStatus?.toLowerCase() || 'unknown',
            a.identityStatus === 'VERIFIED' ? 'badge-ok' : 'badge-pending')
        : el('span', { className: 'subtle' }, 'document review (no IDV vendor configured)')),
    a.identityReason ? el('dt', {}, 'reason') : null,
    a.identityReason ? el('dd', { className: 'subtle' }, a.identityReason) : null,
    el('dt', {}, 'filed'), el('dd', { className: 'mono' }, when(a.submittedAt || a.createdAt)),
    a.refId ? el('dt', {}, 'provisioned') : null,
    a.refId ? el('dd', { className: 'mono' }, a.refId) : null,
    a.reviewNote ? el('dt', {}, 'last note') : null,
    a.reviewNote ? el('dd', { className: 'subtle' }, a.reviewNote) : null));

  // The stake, for the kinds that have one.
  if (a.stake?.required) {
    const s = a.stake;
    card.append(el('div', { className: 'section-label' }, 'Stake'));
    card.append(el('dl', { className: 'kv' },
      el('dt', {}, 'required'), el('dd', { className: 'mono' }, money(s.requiredMinor, s.currency)),
      el('dt', {}, 'paid'), el('dd', { className: 'mono' },
        s.paidMinor ? `${money(s.paidMinor, s.currency)} · ${when(s.paidAt)}` : 'not yet'),
      el('dt', {}, 'id check fee'), el('dd', { className: 'mono' }, money(s.kycFeeMinor, s.currency)),
      el('dt', {}, 'still locked'), el('dd', { className: 'mono' }, money(s.remainingMinor, s.currency))));
  }

  card.append(documentsBlock('Documents', row.documents, a.missingDocuments));

  for (const rv of row.vehicles || []) {
    const v = rv.vehicle;
    card.append(el('div', { className: 'section-label' },
      `Vehicle · ${v.category}${v.active ? ' · active' : ''}`));
    card.append(el('dl', { className: 'kv' },
      el('dt', {}, 'vehicle'), el('dd', {},
        [v.color, v.make, v.model, v.year].filter(Boolean).join(' ') || '—'),
      el('dt', {}, 'plate'), el('dd', { className: 'mono' }, `${v.plate || '—'} (${v.region || 'no region'})`),
      el('dt', {}, 'state'), el('dd', {},
        badge(v.state.toLowerCase(), v.state === 'APPROVED' || v.state === 'COMMUNITY_VERIFIED'
          ? 'badge-ok' : v.state === 'FLAGGED' ? 'badge-bad' : 'badge-pending')),
      el('dt', {}, 'papers'), el('dd', {},
        v.papersExpired
          ? badge('expired', 'badge-bad')
          : el('span', { className: 'mono subtle' },
              `reg ${v.registrationExpiresOn || '—'} · ins ${v.insuranceExpiresOn || '—'}`)));
    card.append(documentsBlock(null, rv.documents, v.missingDocuments));

    const ok = el('button', { className: 'btn', textContent: 'Approve vehicle' });
    const flag = el('button', { className: 'btn btn-danger', textContent: 'Flag vehicle' });
    ok.onclick = () => reviewVehicle(a.id, v.id, true);
    flag.onclick = () => reviewVehicle(a.id, v.id, false);
    card.append(el('div', { className: 'actions' }, ok, flag));
  }

  card.append(partnerActions(a));
  return card;
}

function documentsBlock(label, docs, missing) {
  const wrap = el('div', {});
  if (label) wrap.append(el('div', { className: 'section-label' }, label));
  if (!docs?.length) {
    wrap.append(el('p', { className: 'subtle', style: 'font-size:14px' }, 'None uploaded.'));
  }
  for (const d of docs || []) {
    wrap.append(el('div', { className: 'doc-row' },
      el('span', { className: 'mono' }, d.kind),
      el('span', { style: 'margin-left:auto' },
        // A short-lived signed GET, minted by the API. Opened in a new tab so
        // the console never proxies the bytes themselves.
        el('a', { href: d.url, target: '_blank', rel: 'noreferrer' }, 'View'))));
  }
  if (missing?.length) {
    wrap.append(el('p', { className: 'subtle', style: 'font-size:14px;margin-top:var(--xs)' },
      `Still missing: ${missing.join(', ')}`));
  }
  return wrap;
}

function partnerActions(a) {
  const actions = el('div', { className: 'actions' });

  if (a.status === 'SUBMITTED') {
    const approve = el('button', { className: 'btn btn-primary', textContent: 'Approve' });
    approve.onclick = async () => {
      const provisions = { RESTAURANT: 'a restaurant into the delivery catalog',
        DRIVER: 'a driver into the dispatch registry',
        COURIER: 'a courier into the dispatch registry' }[a.kind] || 'this partner';
      const note = await confirmAction({
        title: `Approve ${a.businessName}?`,
        detail: `This provisions ${provisions} immediately, and grants the verified badge. `
          + (a.kind === 'DRIVER' ? 'It also credits their welcome ride tokens. ' : '')
          + 'It can be undone by suspending, which is not the same as never having approved.',
        confirmLabel: 'Approve', noteLabel: 'Note (optional)'
      });
      if (note === null) return;
      await decide(a.id, 'approve', { note });
    };
    actions.append(approve);

    const reject = el('button', { className: 'btn btn-danger', textContent: 'Reject' });
    reject.onclick = async () => {
      const note = await confirmAction({
        title: `Reject ${a.businessName}?`,
        detail: 'The applicant can edit and resubmit the same application, keeping its '
          + 'documents and your note. Any stake goes back, less what the ID check cost.',
        confirmLabel: 'Reject', danger: true,
        noteLabel: 'Why — the applicant reads this', noteRequired: true
      });
      if (note === null) return;
      await decide(a.id, 'reject', { note });
    };
    actions.append(reject);
  }

  if (a.status === 'APPROVED') {
    const suspend = el('button', { className: 'btn btn-danger', textContent: 'Suspend' });
    suspend.onclick = async () => {
      const note = await confirmAction({
        title: `Suspend ${a.businessName}?`,
        detail: a.kind === 'RESTAURANT'
          ? 'The restaurant leaves the catalog and its menu stays. Approving again brings it back.'
          : 'They stop being offered work. The stake stays locked — a suspension is not a refund.',
        confirmLabel: 'Suspend', danger: true, noteLabel: 'Note (optional)'
      });
      if (note === null) return;
      await decide(a.id, 'suspend', { note });
    };
    actions.append(suspend);
  }

  if (a.status === 'SUSPENDED') {
    const restore = el('button', { className: 'btn btn-primary', textContent: 'Restore' });
    restore.onclick = async () => {
      const note = await confirmAction({
        title: `Restore ${a.businessName}?`,
        detail: 'Approving a suspended partner puts them back exactly where they were — '
          + 'the same provisioned merchant or registration, not a new one.',
        confirmLabel: 'Restore', noteLabel: 'Note (optional)'
      });
      if (note === null) return;
      await decide(a.id, 'approve', { note });
    };
    actions.append(restore);
  }

  if (a.status === 'DRAFT') {
    const submit = el('button', { className: 'btn', textContent: 'Submit for review' });
    submit.onclick = async () => {
      const ok = await confirmAction({
        title: 'Submit this application?',
        detail: 'Files it into the review queue on the applicant\'s behalf. The server still '
          + 'checks everything it would check for them — including their ID, which nobody '
          + 'can pass for somebody else.',
        confirmLabel: 'Submit'
      });
      if (ok === null) return;
      await decide(a.id, 'submit', {});
    };
    actions.append(submit);
  }

  return actions;
}

async function decide(id, verb, body) {
  try {
    await api(`/v1/partner/admin/applications/${id}/${verb}`, { method: 'POST', body });
    toast(`${verb} done.`);
    state.selected = null;
    await refreshPartners();
  } catch (err) {
    toast(err.message, true);
  }
}

async function reviewVehicle(accountId, vehicleId, approved) {
  const note = await confirmAction({
    title: approved ? 'Approve this vehicle?' : 'Flag this vehicle?',
    detail: approved
      ? 'A vehicle is a separate claim from the person. Approving it is what lets dispatch '
        + 'send work for its category.'
      : 'Flagging is not a rejection — a re-upload puts it back in the queue. If it is the '
        + 'driver\'s active vehicle, they stop receiving work.',
    confirmLabel: approved ? 'Approve vehicle' : 'Flag vehicle',
    danger: !approved, noteLabel: 'Note (optional)'
  });
  if (note === null) return;
  try {
    await api(`/v1/partner/admin/applications/${accountId}/vehicles/${vehicleId}/review`,
      { method: 'POST', body: { approved, note } });
    toast(approved ? 'Vehicle approved.' : 'Vehicle flagged.');
    await refreshPartners();
  } catch (err) {
    toast(err.message, true);
  }
}

// ── View: moderation ────────────────────────────────────────────────────────

const mod = { status: 'OPEN', rows: [], selected: null };

async function viewModeration(main) {
  main.replaceChildren(
    el('div', { className: 'main-head' },
      el('div', {},
        el('h1', {}, 'Reports'),
        el('p', {}, 'One queue for every reportable kind. Nothing escalates on its own — '
          + 'a report sits here until a person reads it.'))),
    el('div', { className: 'filters', id: 'mod-filters' }),
    el('div', { id: 'mod-body' }, skeleton()));

  const bar = $('#mod-filters');
  for (const status of ['OPEN', 'ACTIONED', 'DISMISSED']) {
    const chip = el('button', { className: 'chip', textContent: status.toLowerCase() });
    chip.setAttribute('aria-pressed', String(mod.status === status));
    chip.onclick = () => { mod.status = status; mod.selected = null; viewModeration(main); };
    bar.append(chip);
  }
  await loadReports();
}

async function loadReports() {
  try {
    mod.rows = await api(`/v1/moderation/admin/reports?status=${mod.status}&limit=100`);
  } catch (err) {
    $('#mod-body')?.replaceChildren(empty('Could not load the queue', err.message));
    return;
  }
  renderReports();
}

function renderReports() {
  const body = $('#mod-body');
  if (!body) return;
  if (!mod.rows.length) {
    body.replaceChildren(empty('Nothing here', `No ${mod.status.toLowerCase()} reports.`));
    return;
  }
  const rows = el('tbody');
  for (const r of mod.rows) {
    const tr = el('tr', {},
      el('td', {}, el('div', {}, r.targetSummary || '(content gone)'),
        el('div', { className: 'mono muted' }, `${r.targetKind} ${r.targetId.slice(0, 8)}`)),
      el('td', {}, r.reason?.toLowerCase() || '—'),
      el('td', {}, badge(r.status.toLowerCase(), badgeClass(r.status))),
      el('td', { className: 'subtle' }, r.otherOpenReports ? `+${r.otherOpenReports} more` : '—'),
      el('td', { className: 'mono muted' }, when(r.createdAt)));
    tr.setAttribute('aria-selected', String(mod.selected === r.id));
    tr.onclick = () => { mod.selected = r.id; renderReports(); };
    rows.append(tr);
  }
  const table = el('div', { className: 'card', style: 'padding:0;overflow:hidden' },
    el('table', {},
      el('thead', {}, el('tr', {},
        ...['Reported', 'Reason', 'Status', 'Also', 'Filed'].map(h => el('th', {}, h)))),
      rows));

  const chosen = mod.rows.find(r => r.id === mod.selected);
  body.replaceChildren(el('div', { className: 'split' }, table,
    el('div', { className: 'detail' },
      chosen ? reportDetail(chosen) : el('div', { className: 'card-soft' },
        el('p', { className: 'subtle' }, 'Select a report to review it.')))));
}

function reportDetail(r) {
  const card = el('div', { className: 'card' },
    el('h2', {}, r.targetKind.toLowerCase()),
    el('div', { className: 'mono muted', style: 'margin-bottom:var(--md)' }, r.targetId));

  card.append(el('dl', { className: 'kv' },
    el('dt', {}, 'content'), el('dd', {},
      r.targetMissing ? el('span', { className: 'subtle' }, 'already gone')
        : (r.targetSummary || '—')),
    el('dt', {}, 'hidden'), el('dd', {}, r.targetHidden ? badge('hidden', 'badge-off') : 'no'),
    el('dt', {}, 'reason'), el('dd', {}, r.reason || '—'),
    r.note ? el('dt', {}, 'reporter said') : null,
    r.note ? el('dd', { className: 'subtle' }, r.note) : null,
    el('dt', {}, 'reporter'), el('dd', { className: 'mono' }, r.reporterHandle || r.reporterId || '—'),
    el('dt', {}, 'owner'), el('dd', { className: 'mono' }, r.targetOwnerHandle || r.targetOwnerId || '—'),
    el('dt', {}, 'also open'), el('dd', {},
      r.otherOpenReports ? `${r.otherOpenReports} other report(s) on this target` : 'none'),
    el('dt', {}, 'filed'), el('dd', { className: 'mono' }, when(r.createdAt)),
    r.reviewedBy ? el('dt', {}, 'decided by') : null,
    r.reviewedBy ? el('dd', { className: 'subtle' }, `${r.reviewedBy} · ${when(r.reviewedAt)}`) : null,
    r.reviewNote ? el('dt', {}, 'decision note') : null,
    r.reviewNote ? el('dd', { className: 'subtle' }, r.reviewNote) : null));

  if (r.status === 'OPEN') {
    const actions = el('div', { className: 'actions' });
    const decisions = [
      ['HIDE', 'Hide', false, 'Reversible, and the author still sees their own post flagged. '
        + 'The right first move when you are working fast and might be wrong.'],
      ['REMOVE', 'Remove', true, 'The door that only opens outward. The content is gone.'],
      ['SUSPEND', 'Suspend account', true, 'Acts on the person rather than the thing, and '
        + 'disables their sign-in. Refused by name for a business profile, because that would '
        + 'lock out its owner sideways.'],
      ['RESTORE', 'Restore', false, 'Puts back something hidden, and reinstates a suspended account.']
    ];
    for (const [action, label, danger, detail] of decisions) {
      const b = el('button', { className: `btn${danger ? ' btn-danger' : ''}`, textContent: label });
      b.onclick = async () => {
        const note = await confirmAction({
          title: `${label}?`,
          detail: detail + ' One decision closes every open report on the same target.',
          confirmLabel: label, danger, noteLabel: 'Note (optional)'
        });
        if (note === null) return;
        try {
          await api(`/v1/moderation/admin/reports/${r.id}/action`,
            { method: 'POST', body: { action, note } });
          toast(`${label} done.`);
          mod.selected = null;
          await loadReports();
        } catch (err) { toast(err.message, true); }
      };
      actions.append(b);
    }
    const dismiss = el('button', { className: 'btn', textContent: 'Dismiss' });
    dismiss.onclick = async () => {
      const note = await confirmAction({
        title: 'Dismiss this report?',
        detail: 'Closes this report only. Somebody else\'s complaint about the same thing may '
          + 'be a different complaint, so those stay open.',
        confirmLabel: 'Dismiss', noteLabel: 'Note (optional)'
      });
      if (note === null) return;
      try {
        await api(`/v1/moderation/admin/reports/${r.id}/dismiss`, { method: 'POST', body: { note } });
        toast('Dismissed.');
        mod.selected = null;
        await loadReports();
      } catch (err) { toast(err.message, true); }
    };
    actions.append(dismiss);
    card.append(actions);
  }
  return card;
}

// ── View: file an application on somebody's behalf ──────────────────────────

function viewCreate(main) {
  const f = {};
  const field = (key, label, placeholder = '') => {
    const input = el('input', { type: 'text', placeholder });
    f[key] = input;
    return el('label', { className: 'field' }, el('span', {}, label), input);
  };
  const kind = el('select', {},
    ...['RESTAURANT', 'DRIVER', 'COURIER'].map(k => el('option', { value: k }, k)));
  f.kind = kind;

  const submit = el('button', { className: 'btn btn-primary', textContent: 'File application' });
  submit.onclick = async () => {
    const owner = f.owner.value.trim();
    if (!owner) { f.owner.focus(); return; }
    const application = {
      kind: kind.value,
      businessName: f.businessName.value.trim(),
      category: f.category.value.trim() || undefined,
      description: f.description.value.trim() || undefined,
      contactName: f.contactName.value.trim() || undefined,
      contactPhone: f.contactPhone.value.trim() || undefined,
      country: f.country.value.trim() || undefined,
      city: f.city.value.trim() || undefined,
      addressLine: f.addressLine.value.trim() || undefined
    };
    // A profile id is a UUID; anything else is a handle. Checked by shape rather
    // than by asking the operator to say which they pasted.
    const looksLikeUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(owner);
    const body = looksLikeUuid
      ? { ownerProfileId: owner, application }
      : { ownerHandle: owner.replace(/^@/, ''), application };
    try {
      const created = await api('/v1/partner/admin/applications', { method: 'POST', body });
      toast(`Filed as ${created.account?.id?.slice(0, 8) || 'a draft'} — it still needs its documents.`);
    } catch (err) { toast(err.message, true); }
  };

  main.replaceChildren(
    el('div', { className: 'main-head' },
      el('div', {},
        el('h1', {}, 'File an application'),
        el('p', {}, 'Restaurants are created here rather than in the app (decided 2026-07-27). '
          + 'This writes through the merchant\'s own path — you are filling in their form, not a '
          + 'parallel one.'))),
    el('div', { className: 'card', style: 'max-width:640px' },
      el('label', { className: 'field' }, el('span', {}, 'Kind'), kind),
      field('owner', 'Owner — @handle or profile id', '@amina'),
      field('businessName', 'Business name', 'Dar Zellij'),
      field('category', 'Category', 'Moroccan'),
      field('description', 'Description'),
      field('contactName', 'Contact name'),
      field('contactPhone', 'Contact phone', '+212…'),
      field('addressLine', 'Address'),
      field('city', 'City', 'Casablanca'),
      field('country', 'Country', 'MA'),
      el('div', { className: 'actions' }, submit)),
    el('div', { className: 'card-soft', style: 'max-width:640px;margin-top:var(--md)' },
      el('p', { className: 'subtle', style: 'font-size:14px' },
        'Filing it does not submit it. The owner still has to pass their own ID check before '
        + 'this can go to review — nobody can do a liveness check on somebody else\'s behalf.')));
}

// ── View: what this can do ──────────────────────────────────────────────────

function viewHelp(main) {
  const row = (what, how) => el('div', { className: 'doc-row' },
    el('span', { style: 'min-width:220px' }, what),
    el('span', { className: 'subtle' }, how));

  main.replaceChildren(
    el('div', { className: 'main-head' },
      el('div', {}, el('h1', {}, 'What this can do'),
        el('p', {}, 'And, more usefully, what it cannot.'))),
    el('div', { className: 'card' },
      el('h3', {}, 'Covered'),
      el('div', { style: 'margin-top:var(--sm)' },
        row('Partner review', 'queue, documents, approve / reject / suspend / restore'),
        row('Vehicle review', 'approve or flag a driver\'s car, separately from the person'),
        row('Admin-side create', 'file an application for a merchant, and submit it'),
        row('Moderation', 'report queue, hide / remove / suspend / restore / dismiss'))),
    el('div', { className: 'card' },
      el('h3', {}, 'Not covered, on purpose'),
      el('div', { style: 'margin-top:var(--sm)' },
        row('Editing config', 'the platform config registry has no write endpoint yet — '
          + 'values are seeded by migration until real GojoAdmin owns them'),
        row('Menus and storefronts', 'those are the owner\'s own /mine surfaces, driven with '
          + 'their JWT, not an admin mirror'),
        row('Anything with its own database', 'this console stores nothing. Close it and no '
          + 'state is lost, because there was none'))),
    el('div', { className: 'card-soft' },
      el('p', { className: 'subtle', style: 'font-size:14px' },
        'Decisions are signed with whichever credential the server was started with. A '
        + 'platform-admin JWT signs with your name; the break-glass token signs as an '
        + 'anonymous operator, which is fine for a stopgap and not fine as a habit.')));
}

// ── Routing ─────────────────────────────────────────────────────────────────

const VIEWS = { partners: viewPartners, moderation: viewModeration, create: viewCreate, help: viewHelp };

function go(name) {
  for (const btn of document.querySelectorAll('.nav-row')) {
    if (btn.dataset.view === name) btn.setAttribute('aria-current', 'page');
    else btn.removeAttribute('aria-current');
  }
  VIEWS[name]($('#main'));
}

for (const btn of document.querySelectorAll('.nav-row')) {
  btn.onclick = () => go(btn.dataset.view);
}

async function boot() {
  try {
    const who = await (await fetch('/whoami')).json();
    $('#whoami').textContent = `${who.actor} · ${who.api.replace(/^https?:\/\//, '')}`;
    if (!who.named) $('#whoami').classList.remove('muted');
  } catch { /* the masthead is decoration; a failure here must not block the queue */ }

  try {
    const res = await fetch('/api/actuator/health');
    const health = $('#api-health');
    health.textContent = res.ok ? 'api up' : `api ${res.status}`;
    health.className = `badge ${res.ok ? 'badge-ok' : 'badge-bad'}`;
  } catch {
    $('#api-health').textContent = 'api unreachable';
    $('#api-health').className = 'badge badge-bad';
  }

  try {
    const summary = await api('/v1/moderation/admin/reports/summary');
    $('#count-reports').textContent = summary.open || '';
  } catch { /* the badge is a nicety */ }

  go('partners');
}

boot();
