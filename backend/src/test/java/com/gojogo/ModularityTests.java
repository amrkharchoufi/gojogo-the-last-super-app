package com.gojogo;

import org.junit.jupiter.api.Test;
import org.springframework.modulith.core.ApplicationModules;

/**
 * Fails the build if any module reaches into another module's internals.
 * This is the enforced boundary described in ARCHITECTURE.md §2.
 */
class ModularityTests {

    static final ApplicationModules modules = ApplicationModules.of(GojogoApplication.class);

    @Test
    void verifiesModularStructure() {
        modules.verify();
    }
}
