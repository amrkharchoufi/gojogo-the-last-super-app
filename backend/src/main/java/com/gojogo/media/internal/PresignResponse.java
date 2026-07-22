package com.gojogo.media.internal;

record PresignResponse(String uploadUrl, String key, String publicUrl,
                       String contentType, long expiresSeconds) {
}
