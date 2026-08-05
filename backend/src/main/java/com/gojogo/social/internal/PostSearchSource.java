package com.gojogo.social.internal;

import com.gojogo.search.SearchDocument;
import com.gojogo.search.SearchIndexApi;
import com.gojogo.search.SearchKind;
import com.gojogo.search.SearchableContent;
import com.gojogo.social.PostCreated;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.util.Optional;
import java.util.UUID;

/**
 * How a post is findable (Phase 5 M4) — social's implementation of the search
 * plugin, next to its {@code ConversationGuard} and {@code ModeratableContent}
 * siblings. This class is both halves of the seam: the listener on this
 * module's own event that tells search something changed, and the renderer
 * search calls back for the document — so search itself imports nothing from
 * this module. A hidden post stays indexed and inactive, so a restore doesn't
 * need a re-crawl.
 */
@Component
class PostSearchSource implements SearchableContent {

    private final PostRepository posts;
    private final SearchIndexApi index;

    PostSearchSource(PostRepository posts, SearchIndexApi index) {
        this.posts = posts;
        this.index = index;
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    void onPostCreated(PostCreated event) {
        index.reindex(SearchKind.POST, event.postId());
    }

    @Override
    public SearchKind kind() {
        return SearchKind.POST;
    }

    @Override
    public Optional<SearchDocument> render(UUID refId) {
        return posts.findById(refId).map(post -> new SearchDocument(
            "", post.getText(), "", post.getAuthorId(),
            post.getLikeCount() + post.getCommentCount(),
            !post.isHidden()));
    }
}
