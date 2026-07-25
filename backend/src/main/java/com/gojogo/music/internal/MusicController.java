package com.gojogo.music.internal;

import com.gojogo.music.MusicTrackDto;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.UUID;

/**
 * Read-only. There is no ingest endpoint on purpose — the app has no admin
 * role, so a catalog writer would be unauthenticated. Tracks are inserted by
 * the operator (see PROGRESS.md "Seeding the music catalog").
 */
@RestController
class MusicController {

    private final MusicService music;

    MusicController(MusicService music) {
        this.music = music;
    }

    @GetMapping("/v1/music/tracks")
    List<MusicTrackDto> browse(@RequestParam(required = false) String q,
                               @RequestParam(defaultValue = "30") int limit) {
        return music.browse(q, limit);
    }

    @GetMapping("/v1/music/tracks/{trackId}")
    MusicTrackDto get(@PathVariable UUID trackId) {
        return music.find(trackId).orElseThrow(
            () -> new ResponseStatusException(HttpStatus.NOT_FOUND, "No such track"));
    }
}
