package com.gojogo.assistant.internal;

import com.gojogo.assistant.internal.AssistantToolExecutor.AssistantToolOutcome;
import com.gojogo.payments.WalletApi;
import com.gojogo.profile.ProfileApi;
import com.gojogo.profile.ProfileDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;

/**
 * MADELEINE.md §4's agent loop.
 *
 * <p>One loop, no planner/executor split. Build context, call the model, run the
 * tools it asked for, feed the results back, repeat until it stops calling tools
 * or a budget runs out.
 *
 * <p>Three properties are worth stating because each is a decision rather than
 * an implementation detail:
 *
 * <ul>
 *   <li><b>Read tools run in parallel; everything else runs in order.</b> The
 *       calls in one model response are independent by construction — the model
 *       emitted them together without seeing any of their results — so the reads
 *       among them are safe to fan out, and doing so is most of the difference
 *       between a four-second turn and a twelve-second one. Anything that writes
 *       (today: staging a gated action) stays serial and in order, because two
 *       threads racing to raise the same confirm card is exactly the duplicate
 *       nobody would find until it was in front of a user.</li>
 *   <li><b>Budget exhaustion ends the turn honestly.</b> Running out of steps or
 *       out of clock produces a real closing message about where she stopped —
 *       never silence, and never a confident answer built from half the work.</li>
 *   <li><b>Every turn is counted.</b> Input tokens, output tokens and step count
 *       land on the ledger row that closes the turn, from the first turn this
 *       module ever runs. MADELEINE-INFERENCE.md §6's switch trigger is a
 *       decision about $9,000/month and it is owed exact numbers.</li>
 * </ul>
 *
 * <p>Previous turns are replayed into context as prose only — the user's words
 * and Madeleine's, never the tool calls and results of a finished turn. Those
 * live in the ledger for the person reading it, not for the model: §3 persists
 * what replays a story, and re-feeding a completed turn's mechanics would grow
 * the context that §4's cost model is built on for no gain.
 */
@Component
class AssistantTurnRunner {

    private static final Logger log = LoggerFactory.getLogger(AssistantTurnRunner.class);

    /**
     * The one prompt string in this module that is not in
     * {@code tools/madeleine-eval/prompts.py}, because the harness has no
     * budget-exhaustion scenario to have measured it with. It shapes how a turn
     * <em>ends</em>, not how tools are chosen, so it cannot move the numbers §9
     * ranked models on — but it should be added to the harness the next time
     * that file is touched.
     */
    private static final String OUT_OF_BUDGET =
        "You have run out of steps for this turn. Do not call any more tools. In one or two "
            + "sentences, in the user's own language, tell them what you found and exactly "
            + "where you stopped. Do not pretend to have finished.";

    private final AssistantModelClient models;
    private final AssistantToolRegistry registry;
    private final AssistantToolExecutor executor;
    private final AssistantEvents events;
    private final AssistantLedger ledger;
    private final AssistantPolicy policy;
    private final ProfileApi profiles;
    private final WalletApi wallet;
    private final ExecutorService toolPool;

    AssistantTurnRunner(AssistantModelClient models, AssistantToolRegistry registry,
                        AssistantToolExecutor executor, AssistantEvents events,
                        AssistantLedger ledger, AssistantPolicy policy, ProfileApi profiles,
                        WalletApi wallet, ExecutorService assistantToolPool) {
        this.models = models;
        this.registry = registry;
        this.executor = executor;
        this.events = events;
        this.ledger = ledger;
        this.policy = policy;
        this.profiles = profiles;
        this.wallet = wallet;
        this.toolPool = assistantToolPool;
    }

    /**
     * Runs one turn to completion. Never throws: a turn that fails ends with a
     * {@code turn_error} the client can show, because the alternative — a thread
     * dying quietly — is a spinner that never stops.
     */
    void run(UUID userId, UUID conversationId, UUID turnId, String userText) {
        AssistantToolContext context = new AssistantToolContext(userId, conversationId, turnId);
        List<AssistantChatMessage> messages = new ArrayList<>();
        messages.add(AssistantChatMessage.system(AssistantPrompts.BRAIN_SYSTEM));
        messages.add(AssistantChatMessage.system(profileSnapshot(userId)));
        messages.addAll(ledger.tail(conversationId, policy.contextTailMessages()));
        messages.add(AssistantChatMessage.user(userText));

        List<Map<String, Object>> tools = registry.offeredSchemas();
        long deadlineAt = System.nanoTime()
            + Duration.ofSeconds(policy.turnDeadlineSeconds()).toNanos();
        int maxSteps = policy.maxToolCallsPerTurn();

        int steps = 0;
        int inputTokens = 0;
        int outputTokens = 0;
        String finalText = null;
        String failure = null;

        try {
            while (true) {
                if (System.nanoTime() > deadlineAt) {
                    Closing closing = closeOut(messages);
                    finalText = closing.text();
                    inputTokens += closing.inputTokens();
                    outputTokens += closing.outputTokens();
                    break;
                }
                AssistantChatResult result =
                    models.chat(AssistantModelRole.BRAIN, messages, tools, null);
                inputTokens += result.inputTokens();
                outputTokens += result.outputTokens();

                if (!result.hasToolCalls()) {
                    finalText = result.content();
                    break;
                }
                messages.add(AssistantChatMessage.assistantCalling(result.content(),
                    result.toolCalls()));
                events.status(userId, conversationId, turnId, statusFor(result.toolCalls()));

                for (AssistantToolOutcome outcome : runCalls(context, result.toolCalls())) {
                    steps++;
                    messages.add(AssistantChatMessage.toolResult(outcome.call().id(),
                        outcome.payload()));
                    ledger.recordToolCall(conversationId, turnId, outcome);
                    if (outcome.actionId() != null) {
                        ledger.pendingAction(outcome.actionId())
                            .ifPresent(action -> events.actionPending(userId, conversationId,
                                turnId, action));
                    }
                }
                if (steps >= maxSteps) {
                    Closing closing = closeOut(messages);
                    finalText = closing.text();
                    inputTokens += closing.inputTokens();
                    outputTokens += closing.outputTokens();
                    break;
                }
            }
        } catch (AssistantModelClient.AssistantModelException modelDown) {
            log.warn("Madeleine turn {} could not reach the model: {}", turnId,
                modelDown.toString());
            failure = "Madeleine is unavailable right now. Nothing was changed.";
        } catch (RuntimeException e) {
            log.error("Madeleine turn {} failed", turnId, e);
            failure = "Something went wrong on this turn. Nothing was changed.";
        }

        if (failure != null) {
            // No ledger row: nothing was said, and a MADELEINE row asserting an
            // apology she never produced would be a fabricated message in a
            // ledger whose whole value is that it is true.
            events.turnError(userId, conversationId, turnId, failure);
            return;
        }

        String prose = finalText == null || finalText.isBlank()
            ? "I could not put an answer together for that." : finalText.strip();
        ledger.recordReply(conversationId, turnId, prose,
            models.modelId(AssistantModelRole.BRAIN), inputTokens, outputTokens, steps);
        events.token(userId, conversationId, turnId, prose);
        events.turnDone(userId, conversationId, turnId);
    }

    // MARK: The steps

    /**
     * Reads fan out; anything that writes stays in order.
     *
     * <p>Results come back in the order the model asked for them regardless,
     * because a tool result message is matched to its call by id and a model
     * reading them out of order is a model reading a different conversation.
     */
    private List<AssistantToolOutcome> runCalls(AssistantToolContext context,
                                                List<AssistantToolCall> calls) {
        List<CompletableFuture<AssistantToolOutcome>> pending = new ArrayList<>(calls.size());
        for (AssistantToolCall call : calls) {
            boolean parallelSafe = registry.find(call.name())
                .map(tool -> tool.toolClass() == AssistantToolClass.READ)
                .orElse(false);
            if (parallelSafe) {
                pending.add(CompletableFuture.supplyAsync(
                    () -> executor.execute(context, call), toolPool));
            } else {
                pending.add(CompletableFuture.completedFuture(executor.execute(context, call)));
            }
        }
        return pending.stream().map(CompletableFuture::join).toList();
    }

    /** The closing call's prose and what it cost. A record rather than two
     *  fields because this bean is a singleton and turns run concurrently. */
    private record Closing(String text, int inputTokens, int outputTokens) {
    }

    /**
     * One final call with <b>no tools at all</b>, so it cannot extend the loop it
     * was called to end. Costs one round trip past the deadline, which is the
     * price of ending honestly rather than with a canned English sentence in a
     * French conversation — and its tokens are counted like any others.
     */
    private Closing closeOut(List<AssistantChatMessage> messages) {
        List<AssistantChatMessage> closing = new ArrayList<>(messages);
        closing.add(AssistantChatMessage.system(OUT_OF_BUDGET));
        try {
            AssistantChatResult result =
                models.chat(AssistantModelRole.BRAIN, closing, List.of(), null);
            if (result.content() != null && !result.content().isBlank()) {
                return new Closing(result.content(), result.inputTokens(),
                    result.outputTokens());
            }
            return new Closing(exhausted(), result.inputTokens(), result.outputTokens());
        } catch (RuntimeException e) {
            log.warn("Madeleine could not write a closing message: {}", e.toString());
            return new Closing(exhausted(), 0, 0);
        }
    }

    private static String exhausted() {
        return "I got partway through that and ran out of time before finishing. "
            + "Nothing was changed — ask me again and I will pick it up.";
    }

    // MARK: Context

    /**
     * The user profile snapshot §4 puts in front of the conversation.
     *
     * <p>Facts the model would otherwise have to spend a tool call on, and
     * nothing more. No balance — that is {@code get_wallet}'s to answer freshly,
     * and a number pinned into a system message goes stale inside a turn.
     */
    private String profileSnapshot(UUID userId) {
        Optional<ProfileDto> profile = profiles.findById(userId);
        StringBuilder snapshot = new StringBuilder("About the person you are helping: ");
        profile.ifPresent(me -> snapshot.append("they are ").append(me.displayName())
            .append(" (@").append(me.handle()).append("). "));
        snapshot.append("Money on this platform is in ").append(wallet.currency())
            .append(", always as integer minor units. ");
        snapshot.append("Today is ").append(LocalDate.now()).append(".");
        return snapshot.toString();
    }

    private static String statusFor(List<AssistantToolCall> calls) {
        return switch (calls.getFirst().name()) {
            case "search_all" -> "Searching…";
            case "search_restaurants", "get_menu" -> "Looking at restaurants…";
            case "search_listings", "get_listing" -> "Looking through the marketplace…";
            case "quote_ride", "get_ride_status" -> "Checking rides…";
            case "get_wallet" -> "Checking your wallet…";
            case "get_my_bookings" -> "Checking your bookings…";
            case "get_profile" -> "Getting your details…";
            default -> "Working on it…";
        };
    }
}
