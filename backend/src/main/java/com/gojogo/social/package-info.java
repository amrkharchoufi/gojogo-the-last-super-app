/**
 * Social module — feed, posts, stories, comments, likes, follows
 * ({@code social} schema).
 *
 * <p>Exposes {@link com.gojogo.social.SocialGraphApi} so other verticals can
 * read the follow graph (Watch shows a channel's follower count as its
 * subscriber count) without a second graph of their own. Writes to the graph
 * stay on this module's REST surface, where the follow event is published.
 */
@org.springframework.modulith.ApplicationModule(displayName = "Social")
package com.gojogo.social;
