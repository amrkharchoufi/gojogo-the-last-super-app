package com.gojogo.config;

/**
 * What any module may ask the config registry. Three readers, because there are
 * only three shapes of policy value: a word, a number, and a switch.
 *
 * <p>Every method takes the caller's own default and returns it for a key that
 * is missing, blank, or unparseable. There is intentionally no
 * "required" variant: a config table that can make the platform refuse to serve
 * requests is a config table nobody dares edit, and the point of this module is
 * that editing it is safe.
 *
 * <p>Callers should read a knob where they use it rather than caching it in a
 * field — the implementation already caches, and a value held in a field for
 * the lifetime of the process is a value that cannot be changed without a
 * deploy, which defeats the exercise.
 */
public interface ConfigApi {

    /** @param key dotted and namespaced by the reading module, e.g. {@code payments.topup.min.minor} */
    String string(String key, String defaultValue);

    /** Money in minor units, durations in whatever unit the key names, counts, basis points. */
    long number(String key, long defaultValue);

    /** {@code true}/{@code yes}/{@code on}/{@code 1} are all true; anything else is false. */
    boolean flag(String key, boolean defaultValue);
}
