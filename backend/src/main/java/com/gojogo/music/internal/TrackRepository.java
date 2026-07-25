package com.gojogo.music.internal;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.UUID;

interface TrackRepository extends JpaRepository<Track, UUID> {

    /** Default browse: hand-ranked first, then most used. */
    @Query("select t from Track t where t.active = true "
        + "order by case when t.trendingRank is null then 1 else 0 end, "
        + "t.trendingRank asc, t.useCount desc, t.title asc")
    List<Track> trending(Pageable page);

    @Query("select t from Track t where t.active = true and ("
        + "lower(t.title) like :needle or lower(t.artist) like :needle) "
        + "order by t.useCount desc, t.title asc")
    List<Track> search(@Param("needle") String needle, Pageable page);

    @Modifying
    @Query("update Track t set t.useCount = t.useCount + 1 where t.id = :trackId")
    void bumpUseCount(@Param("trackId") UUID trackId);
}
