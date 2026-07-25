package com.gojogo.music.internal;

import com.gojogo.music.MusicApi;
import com.gojogo.music.MusicTrackDto;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.UUID;

/** Catalog reads, plus the {@link MusicApi} other modules use. */
@Service
class MusicService implements MusicApi {

    private static final int MAX_LIMIT = 50;

    private final TrackRepository tracks;

    MusicService(TrackRepository tracks) {
        this.tracks = tracks;
    }

    /** Trending when the query is blank, otherwise a title/artist match. */
    @Transactional(readOnly = true)
    List<MusicTrackDto> browse(String query, int limit) {
        var page = PageRequest.of(0, Math.min(Math.max(limit, 1), MAX_LIMIT));
        String cleaned = query == null ? "" : query.trim();
        List<Track> rows = cleaned.isEmpty()
            ? tracks.trending(page)
            : tracks.search("%" + cleaned.toLowerCase(Locale.ROOT) + "%", page);
        return rows.stream().map(MusicService::dto).toList();
    }

    @Override
    @Transactional(readOnly = true)
    public Optional<MusicTrackDto> find(UUID trackId) {
        return tracks.findById(trackId).filter(Track::isActive).map(MusicService::dto);
    }

    @Override
    @Transactional
    public void recordUse(UUID trackId) {
        tracks.bumpUseCount(trackId);
    }

    static MusicTrackDto dto(Track track) {
        return new MusicTrackDto(track.getId(), track.getTitle(), track.getArtist(),
            track.getArtworkUrl(), track.getAudioUrl(), track.getDurationMs());
    }
}
