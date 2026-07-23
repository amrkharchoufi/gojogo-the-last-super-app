package com.gojogo.messaging.internal;

import com.gojogo.media.MediaApi;
import com.gojogo.messaging.internal.MessagingRepository.OtpRecord;
import com.gojogo.messaging.internal.MessagingRepository.WorldProfile;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.HexFormat;
import java.util.Optional;
import java.util.UUID;

/**
 * My World identity: phone verification (OTP) and the phone-keyed messaging
 * profile (its own display name + avatar, separate from the social profile).
 * Mirrors WhatsApp's setup logic — one human, one verified phone, one World
 * identity per app account.
 */
@Service
class WorldService {

    private static final Duration OTP_TTL = Duration.ofMinutes(10);
    private static final int MAX_ATTEMPTS = 5;

    private final MessagingRepository repo;
    private final WorldSmsSender sms;
    private final WorldProperties props;
    private final MediaApi media;
    private final SecureRandom random = new SecureRandom();

    WorldService(MessagingRepository repo, WorldSmsSender sms, WorldProperties props, MediaApi media) {
        this.repo = repo;
        this.sms = sms;
        this.props = props;
        this.media = media;
    }

    WorldProfileDto me(UUID profileId) {
        return repo.getWorldProfile(profileId)
            .map(p -> new WorldProfileDto(p.setupComplete(), p.phone(), p.displayName(), p.avatarUrl()))
            .orElseGet(() -> new WorldProfileDto(false, null, null, null));
    }

    StartPhoneResponse startPhone(UUID profileId, String rawPhone) {
        String phone = normalize(rawPhone);
        String code = String.format("%06d", random.nextInt(1_000_000));
        repo.putOtp(profileId, phone, hash(profileId, code), Instant.now().plus(OTP_TTL), 0);
        boolean sent = sms.sendCode(phone, code);
        return new StartPhoneResponse(sent);
    }

    void verifyPhone(UUID profileId, String rawPhone, String code) {
        String phone = normalize(rawPhone);
        OtpRecord otp = repo.getOtp(profileId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Request a code first"));
        if (!otp.phone().equals(phone)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Phone number changed; request a new code");
        }
        if (Instant.now().isAfter(otp.expiresAt())) {
            repo.deleteOtp(profileId);
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Code expired; request a new one");
        }
        if (otp.attempts() >= MAX_ATTEMPTS) {
            repo.deleteOtp(profileId);
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS, "Too many attempts; request a new code");
        }
        boolean ok = constantTimeEquals(otp.codeHash(), hash(profileId, code))
            || (props.hasDevCode() && props.devOtpCode().equals(code));
        if (!ok) {
            repo.putOtp(profileId, otp.phone(), otp.codeHash(), otp.expiresAt(), otp.attempts() + 1);
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Incorrect code");
        }
        repo.deleteOtp(profileId);

        WorldProfile existing = repo.getWorldProfile(profileId).orElse(null);
        WorldProfile updated = new WorldProfile(
            profileId, phone,
            existing != null ? existing.displayName() : null,
            existing != null ? existing.avatarUrl() : null,
            Instant.now(),
            existing != null && existing.displayName() != null && !existing.displayName().isBlank());
        repo.putWorldProfile(updated);
        repo.putPhoneIndex(phone, profileId);
    }

    WorldProfileDto updateProfile(UUID profileId, UpdateWorldProfileRequest req) {
        WorldProfile existing = repo.getWorldProfile(profileId)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Verify your phone number first"));
        if (existing.phone() == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Verify your phone number first");
        }
        String name = req.displayName() != null ? req.displayName().trim() : existing.displayName();
        String avatar = req.avatarUrl() != null ? req.avatarUrl() : existing.avatarUrl();
        boolean complete = name != null && !name.isBlank();
        WorldProfile updated = new WorldProfile(
            profileId, existing.phone(), name, avatar, existing.verifiedAt(), complete);
        repo.putWorldProfile(updated);
        if (req.avatarUrl() != null && !req.avatarUrl().isBlank()) {
            media.markReferenced(java.util.List.of(req.avatarUrl()));
        }
        return new WorldProfileDto(updated.setupComplete(), updated.phone(),
            updated.displayName(), updated.avatarUrl());
    }

    WorldUserDto byPhone(UUID callerId, String rawPhone) {
        String phone = normalize(rawPhone);
        UUID id = repo.profileIdForPhone(phone)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                "No GojoGo My World account for that number yet"));
        WorldProfile p = repo.getWorldProfile(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Not found"));
        return new WorldUserDto(id, p.displayName(), p.avatarUrl(), p.phone());
    }

    // ---- helpers ----------------------------------------------------------

    /** Light E.164 normalization: keep a leading +, strip separators, validate length. */
    static String normalize(String raw) {
        if (raw == null) throw badPhone();
        String trimmed = raw.trim();
        boolean plus = trimmed.startsWith("+") || trimmed.startsWith("00");
        String digits = trimmed.replaceAll("[^0-9]", "");
        if (trimmed.startsWith("00")) digits = digits.substring(2);
        if (digits.length() < 8 || digits.length() > 15) throw badPhone();
        return "+" + digits;
    }

    private static ResponseStatusException badPhone() {
        return new ResponseStatusException(HttpStatus.BAD_REQUEST, "Enter a valid phone number with country code");
    }

    private String hash(UUID profileId, String code) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            md.update(profileId.toString().getBytes(StandardCharsets.UTF_8));
            md.update((byte) ':');
            byte[] digest = md.digest(code.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (Exception e) {
            throw new IllegalStateException("hash failed", e);
        }
    }

    private static boolean constantTimeEquals(String a, String b) {
        return MessageDigest.isEqual(a.getBytes(StandardCharsets.UTF_8), b.getBytes(StandardCharsets.UTF_8));
    }
}
