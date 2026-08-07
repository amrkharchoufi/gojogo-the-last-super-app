/**
 * Social module — feed, posts, stories, comments, likes, follows
 * ({@code social} schema).
 *
 * <p>Exposes {@link com.gojogo.social.SocialGraphApi} so other verticals can
 * read the follow graph (Watch shows a channel's follower count as its
 * subscriber count) without a second graph of their own. Writes to the graph
 * stay on this module's REST surface, where the follow event is published.
 *
 * <p>Also exposes {@link com.gojogo.social.SocialContentApi}: thumbnails and
 * text snippets for posts, story frames and comments, so the activity feed can
 * say <em>which</em> post a row is about without reading this module's tables.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Social")
package com.gojogo.social;
