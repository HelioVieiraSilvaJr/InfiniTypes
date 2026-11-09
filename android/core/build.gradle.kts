plugins {
    alias(libs.plugins.kotlin.jvm)
}

kotlin {
    jvmToolchain(17)
}

sourceSets {
    main {
        // Prompts do refinamento, compartilhados com as outras plataformas
        resources.srcDir("../../shared/prompts")
    }
}

dependencies {
    // No Android o org.json já vem no sistema; aqui só para compilar e testar.
    compileOnly(libs.json)
    testImplementation(libs.json)
    testImplementation(libs.junit)
}

tasks.test {
    // Casos de conformidade, os mesmos dos testes das outras plataformas
    systemProperty("conformance.dir", rootProject.file("../shared/conformance").absolutePath)
    inputs.dir(rootProject.file("../shared/conformance"))
}
