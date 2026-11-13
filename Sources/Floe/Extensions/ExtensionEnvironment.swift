//
//  ExtensionEnvironment.swift
//  Project: Floe
//
//  Copyright (Floe) © 2026 René Jiménez
//  Licensed under the GNU AGPLv3

/// What an extension's process gets of the login shell's environment: the variables below, so a token the shell
/// exports stays out, unless the extension's page in Settings passes it all of them. Floe adds its own afterwards.
nonisolated enum ExtensionEnvironment {
    /// Variables that pass, by exact name or by prefix, each group with why an extension or a tool it starts needs
    /// them. Names are exact where a prefix would also let a secret through, as `HOMEBREW_` would `HOMEBREW_GITHUB_API_TOKEN`.
    struct Allowance {
        var names: Set<String> = []
        var prefixes: [String] = []
        let reason: String
    }

    static let allowances: [Allowance] = [
        Allowance(names: ["PATH"], reason: "every program started by name is looked up in it, with the folders Floe adds"),
        Allowance(names: ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR"], reason: "who and where the user is; Node's os helpers read them"),
        Allowance(names: ["LANG", "TZ", "__CF_USER_TEXT_ENCODING"], prefixes: ["LC_"], reason: "text encoding, language and time zone, for the extension and the tools it starts"),
        Allowance(names: ["XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME"], reason: "where tools keep their configuration"),
        Allowance(names: ["EDITOR", "VISUAL"], reason: "the user's editor, for opening a file in it"),
        Allowance(
            names: ["http_proxy", "https_proxy", "all_proxy", "no_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "NODE_EXTRA_CA_CERTS", "SSL_CERT_FILE", "SSL_CERT_DIR"],
            reason: "reaching the network behind a company proxy or its certificate"
        ),
        Allowance(names: ["SSH_AUTH_SOCK"], reason: "git and ssh find the SSH agent through it; a socket's path, though it lets them use the agent's keys"),
        Allowance(names: ["HOMEBREW_PREFIX", "HOMEBREW_CELLAR", "HOMEBREW_REPOSITORY"], reason: "where Homebrew is, for extensions that run brew"),
        Allowance(
            names: ["NVM_DIR", "FNM_DIR", "VOLTA_HOME", "BUN_INSTALL", "CARGO_HOME", "RUSTUP_HOME", "GOPATH", "JAVA_HOME", "ANDROID_HOME", "ANDROID_SDK_ROOT", "ZDOTDIR"],
            reason: "where a toolchain or the shell's own files are"
        ),
        Allowance(names: ["DEVELOPER_DIR", "SDKROOT", "TOOLCHAINS"], reason: "which Xcode and SDK Apple's tools use, as for a swift: import's build"),
        Allowance(
            names: ["KUBECONFIG", "DOCKER_HOST", "AWS_PROFILE", "AWS_REGION", "AWS_DEFAULT_REGION", "CODEX_HOME", "CLAUDE_CONFIG_DIR"],
            reason: "which configuration a tool reads; they point at it and hold no secret"
        ),
        Allowance(names: ["NODE_ENV"], reason: "React picks its build from it; Floe sets production when the shell has none"),
    ]

    private static let names = allowances.reduce(into: Set<String>()) { $0.formUnion($1.names) }
    private static let prefixes = allowances.flatMap(\.prefixes)

    static func isAllowed(_ name: String) -> Bool {
        names.contains(name) || prefixes.contains { name.hasPrefix($0) }
    }

    /// The allowed variables of `environment`, or all of them for an extension the user passes everything.
    static func handedOn(_ environment: [String: String], passesShellEnvironment: Bool) -> [String: String] {
        passesShellEnvironment ? environment : environment.filter { isAllowed($0.key) }
    }
}
