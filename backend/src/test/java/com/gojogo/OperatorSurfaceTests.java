package com.gojogo;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.config.BeanDefinition;
import org.springframework.context.annotation.ClassPathScanningCandidateComponentProvider;
import org.springframework.core.annotation.AnnotatedElementUtils;
import org.springframework.core.type.filter.AnnotationTypeFilter;
import org.springframework.util.AntPathMatcher;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.lang.reflect.Method;
import java.lang.reflect.Parameter;
import java.util.ArrayList;
import java.util.List;


import static org.assertj.core.api.Assertions.assertThat;

/**
 * Every operator surface has to be {@code permitAll} in the security chain, and
 * this is the test that says so.
 *
 * <p><b>It exists because the fourth one was left out and nothing noticed.</b>
 * The break-glass path — {@code X-Partner-Admin-Token} and no bearer token at
 * all — is how an operator works a queue when nobody is signed into the
 * {@code platform-admin} Cognito group, and it is the runbook PROGRESS.md
 * documents. Those endpoints therefore have to be permitted in the chain and
 * authorize themselves in the controller through {@code PlatformAdminApi}.
 * Phase 4 M6 shipped the dispute queue — the only operator surface in the system
 * that <em>moves money</em> — without adding its prefix to that list, so the
 * chain's {@code authenticated()} 401'd the token-only call before
 * {@code DisputeAdminController} ever ran. Nothing failed on the way out: the
 * unit tests call the service directly, the deploy was green, and the surface
 * looked present. It was found by the first person to try the documented curl,
 * two months of milestones later.
 *
 * <p>Structural rather than behavioural, for the same reason
 * {@code CourierListenerTransactionTests} is: reproducing it needs a real
 * filter chain against a real request, which is exactly the shape of thing this
 * repo cannot run locally and therefore keeps discovering in production. What
 * <em>can</em> be checked is the rule — <b>if a method reads the break-glass
 * header, its path must be one the chain lets through unauthenticated</b> — and
 * the discovery is a classpath scan rather than a list, so the fifth operator
 * surface is covered on the day it is written rather than on the day somebody
 * curls it.
 */
class OperatorSurfaceTests {

    /** The header that means "there is no JWT coming". */
    private static final String BREAK_GLASS_HEADER = "X-Partner-Admin-Token";

    private static final AntPathMatcher PATHS = new AntPathMatcher();

    @Test
    @DisplayName("every endpoint that accepts the break-glass token is permitted in the chain")
    void breakGlassEndpointsArePermitted() {
        List<String> found = breakGlassEndpoints();

        // If this is empty the scan has broken, and a green test would then be
        // saying nothing at all — which is the failure mode of every structural
        // test that discovers its own subjects.
        assertThat(found)
            .as("the classpath scan found no break-glass endpoints at all")
            .isNotEmpty();

        for (String path : found) {
            assertThat(SecurityConfig.OPERATOR_SURFACES)
                .as("%s reads %s, so a caller with no bearer token must reach it — "
                    + "add its prefix to SecurityConfig.OPERATOR_SURFACES", path, BREAK_GLASS_HEADER)
                .anyMatch(pattern -> PATHS.match(pattern, path));
        }
    }

    @Test
    @DisplayName("no operator surface is permitted that nothing actually serves")
    void everyPermittedSurfaceIsServed() {
        List<String> found = breakGlassEndpoints();

        // The other direction, and it is not symmetry for its own sake: a
        // pattern left behind by a deleted controller is a hole in the chain
        // that reads, in a diff, exactly like a hole that is still load-bearing.
        for (String pattern : SecurityConfig.OPERATOR_SURFACES) {
            assertThat(found)
                .as("%s is permitAll but no endpoint under it takes the break-glass token",
                    pattern)
                .anyMatch(path -> PATHS.match(pattern, path));
        }
    }

    // MARK: The scan

    /** Every mapped path whose handler declares the break-glass header. */
    private static List<String> breakGlassEndpoints() {
        ClassPathScanningCandidateComponentProvider scanner =
            new ClassPathScanningCandidateComponentProvider(false);
        scanner.addIncludeFilter(new AnnotationTypeFilter(RestController.class));

        List<String> paths = new ArrayList<>();
        for (BeanDefinition candidate : scanner.findCandidateComponents("com.gojogo")) {
            Class<?> controller = load(candidate.getBeanClassName());
            for (String prefix : mappedPaths(controller, "")) {
                for (Method method : controller.getDeclaredMethods()) {
                    if (!readsBreakGlassHeader(method)) continue;
                    paths.addAll(mappedPaths(method, prefix));
                }
            }
        }
        return paths;
    }

    private static boolean readsBreakGlassHeader(Method method) {
        for (Parameter parameter : method.getParameters()) {
            RequestHeader header = parameter.getAnnotation(RequestHeader.class);
            if (header == null) continue;
            String name = header.name().isEmpty() ? header.value() : header.name();
            if (BREAK_GLASS_HEADER.equalsIgnoreCase(name)) return true;
        }
        return false;
    }

    /**
     * The paths an element maps, prefixed. {@code @GetMapping} and friends are
     * meta-annotated with {@code @RequestMapping}, so one lookup covers all of
     * them; an element with no mapping contributes the prefix unchanged, which
     * is what makes a controller with no class-level {@code @RequestMapping}
     * (every one in this codebase today) come out right.
     */
    private static List<String> mappedPaths(java.lang.reflect.AnnotatedElement element,
                                            String prefix) {
        RequestMapping mapping =
            AnnotatedElementUtils.findMergedAnnotation(element, RequestMapping.class);
        String[] values = mapping == null ? new String[0]
            : mapping.path().length > 0 ? mapping.path() : mapping.value();
        if (values.length == 0) return List.of(prefix);
        return java.util.Arrays.stream(values).map(value -> prefix + value).toList();
    }

    private static Class<?> load(String name) {
        try {
            return Class.forName(name);
        } catch (ClassNotFoundException scannerFoundSomethingItCannotLoad) {
            throw new IllegalStateException(scannerFoundSomethingItCannotLoad);
        }
    }
}
