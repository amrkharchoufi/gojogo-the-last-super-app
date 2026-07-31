/**
 * Platform config registry — the one place product policy lives
 * ({@code platform} schema, SPECS.md §14).
 *
 * <p>The distinction this module exists to enforce: a value whose wrongness is a
 * <em>business</em> mistake (a fee, a stake amount, a TTL, a radius, a limit)
 * belongs in the database and changes without a deploy; a value whose wrongness
 * means the process cannot start (a hostname, a credential, a pool size) belongs
 * in {@code application.yml}. Before this module, everything was the second
 * kind, which is why {@code maxBusinessesPerOwner} shipped as a Java constant.
 *
 * <p><strong>Values are effective-dated and never updated in place.</strong> A
 * change inserts a row with a later {@code effective_from}; a read takes the
 * newest row that has already taken effect. That is what makes "what was the
 * platform fee last March" answerable from the table — the question every
 * payment dispute eventually becomes — and it is the mechanism the vision means
 * by changing token prices without changing the driver experience.
 *
 * <p>Consumers read {@link com.gojogo.config.ConfigApi} and always pass a
 * compiled-in default. That is not defensive habit: an empty table must behave
 * exactly like a populated one, so a fresh environment, a failed read and a typo
 * in a value all land on the same well-understood number instead of on zero.
 *
 * <p>There is no write endpoint yet, deliberately. Values are seeded by
 * migration until GoJoAdmin exists to edit them — the same posture the music
 * catalog and partner review took, because this app has no admin surface and a
 * half-guarded one is worse than waiting for the console that will own it.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Platform config")
package com.gojogo.config;
