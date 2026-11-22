import Foundation
import Testing

@testable import WalletCore

@Suite("Chain source preference")
struct ChainSourcePreferenceTests {
    @Test("The default uses the public server and needs no URL")
    func defaultIsUsable() {
        let preference = ChainSourcePreference.default
        #expect(preference.kind == .publicServer)
        #expect(preference.resolvedURL == nil)
        #expect(preference.isUsable)
    }

    @Test("A bare host on the local network becomes a plain-HTTP URL")
    func normalisesBareLocalHost() {
        #expect(ChainSourcePreference.normalize("umbrel.local:3002") == "http://umbrel.local:3002")
        #expect(ChainSourcePreference.normalize("  192.168.1.20:3002  ") == "http://192.168.1.20:3002")
        #expect(ChainSourcePreference.normalize("localhost:3002") == "http://localhost:3002")
        #expect(ChainSourcePreference.normalize("127.0.0.1:3002") == "http://127.0.0.1:3002")
        #expect(ChainSourcePreference.normalize("10.1.2.3") == "http://10.1.2.3")
        #expect(ChainSourcePreference.normalize("172.20.0.5:3002") == "http://172.20.0.5:3002")
        #expect(ChainSourcePreference.normalize("169.254.7.7") == "http://169.254.7.7")
        #expect(ChainSourcePreference.normalize("[::1]:3002") == "http://[::1]:3002")
        #expect(
            ChainSourcePreference.normalize("abcdefghij234567.onion:3002")
                == "http://abcdefghij234567.onion:3002"
        )
    }

    @Test("A bare host that is not provably local defaults to HTTPS, not cleartext")
    func defaultsRemoteHostsToTLS() {
        #expect(ChainSourcePreference.normalize("esplora.example.com") == "https://esplora.example.com")
        #expect(
            ChainSourcePreference.normalize("esplora.example.com:3002/api")
                == "https://esplora.example.com:3002/api"
        )
        #expect(ChainSourcePreference.normalize("8.8.8.8:3002") == "https://8.8.8.8:3002")
        #expect(ChainSourcePreference.normalize("172.32.0.5") == "https://172.32.0.5")
        #expect(ChainSourcePreference.normalize("10.1.2.3.example.com") == "https://10.1.2.3.example.com")
        #expect(ChainSourcePreference.normalize("umbrel") == "https://umbrel")
    }

    @Test("An explicit scheme is never overridden")
    func explicitSchemeWins() {
        #expect(
            ChainSourcePreference.normalize("http://esplora.example.com")
                == "http://esplora.example.com"
        )
        #expect(ChainSourcePreference.normalize("HTTP://node.local") == "HTTP://node.local")
    }

    @Test("An explicit scheme and trailing slashes are respected and tidied")
    func normalisesSchemeAndSlashes() {
        #expect(
            ChainSourcePreference.normalize("https://mempool.space/signet/api/")
                == "https://mempool.space/signet/api"
        )
        #expect(ChainSourcePreference.normalize("http://node.local///") == "http://node.local")
    }

    @Test("Unusable input normalises to nil")
    func rejectsUnusableInput() {
        #expect(ChainSourcePreference.normalize("") == nil)
        #expect(ChainSourcePreference.normalize("   ") == nil)
        #expect(ChainSourcePreference.normalize("http://") == nil)

        let halfTyped = ChainSourcePreference(kind: .ownNode, customURL: "  ")
        #expect(halfTyped.resolvedURL == nil)
        #expect(!halfTyped.isUsable, "an unusable own-node setting must not be treated as valid")
    }

    @Test("An own-node preference round-trips through storage")
    func codableRoundTrip() throws {
        let preference = ChainSourcePreference(kind: .ownNode, customURL: "http://node.local:3002")
        let data = try JSONEncoder().encode(preference)
        #expect(try JSONDecoder().decode(ChainSourcePreference.self, from: data) == preference)
    }
}

extension ChainSourcePreferenceTests {
    @Test("The gap limit defaults to the BIP44 convention")
    func gapLimitDefault() {
        #expect(ChainSourcePreference().gapLimit == 20)
        #expect(ChainSourcePreference.defaultGapLimit == 20)
    }

    @Test("A gap limit is clamped to something a scan can finish")
    func gapLimitIsClamped() {
        #expect(ChainSourcePreference(gapLimit: 0).gapLimit == 1)
        #expect(ChainSourcePreference(gapLimit: 10_000).gapLimit == ChainSourcePreference.maximumGapLimit)
        #expect(ChainSourcePreference(gapLimit: 50).gapLimit == 50)
    }

    @Test("A preference written before the gap limit existed reads back with the convention")
    func gapLimitDecodesFromLegacy() throws {
        let legacy = #"{"kind":"publicServer","customURL":""}"#
        let decoded = try JSONDecoder().decode(
            ChainSourcePreference.self, from: Data(legacy.utf8)
        )
        #expect(decoded.gapLimit == ChainSourcePreference.defaultGapLimit)
    }

    @Test("The gap limit survives storage")
    func gapLimitRoundTrips() throws {
        let preference = ChainSourcePreference(kind: .ownNode, customURL: "node.local:3002", gapLimit: 120)
        let decoded = try JSONDecoder().decode(
            ChainSourcePreference.self, from: try JSONEncoder().encode(preference)
        )
        #expect(decoded.gapLimit == 120)
        #expect(decoded == preference)
    }
}
