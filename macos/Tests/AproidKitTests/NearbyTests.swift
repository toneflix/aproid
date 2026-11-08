import XCTest
@testable import AproidKit

final class NearbyTests: XCTestCase {
    private let answer = Nearby.Answer(deviceId: "a1b2c3d4e5f60718293a4b5c6d7e8f90", addresses: ["192.168.43.1"], port: 1716, ssid: "Aproid-1234", password: "secret-pass")

    func testRequestRoundTrips() throws {
        let request = Nearby.Request(deviceId: "a1b2c3d4e5f60718293a4b5c6d7e8f90", want: .hotspot)

        XCTAssertEqual(Nearby.Request(bytes: request.bytes()), request)
        XCTAssertNil(Nearby.Request(bytes: Data(#"{"id":"../x","want":"connect"}"#.utf8)))
    }

    /// Sealed by a separate implementation of the same format; the Kotlin tests open the same bytes.
    func testOpensTheSharedFixture() throws {
        let opened = try Nearby.open(Data(base64Encoded: Self.fixtureAnswer)!, privateKeyPEM: Self.fixtureKey)

        XCTAssertEqual(opened, answer)
    }

    func testRefusesAChangedAnswer() throws {
        var sealed = Data(base64Encoded: Self.fixtureAnswer)!
        sealed[sealed.count - 1] ^= 1

        XCTAssertThrowsError(try Nearby.open(sealed, privateKeyPEM: Self.fixtureKey))
    }

    // A throwaway key made only for this test.
    private static let fixtureKey = """
-----BEGIN PRIVATE KEY-----
MIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQCZx7RZNyPVF0cX
6n9vlBG8mK45aFejL8J8C0le4/hTcYhCFQmI8dbs0NfO54yKKmf8ctKEGPVxZm6Q
SDK1Fo5SceQb1IJ9oM/SYTQZl9z+y5co40tAcnKhEHc6Ea2Fi7IxsyM7d1/E4vUm
kGZtFni5SMc+qJ6iN6H/m09q8KlZbuXGg78LVQjf4LSAhGRXW41YXet4rKV7hDTs
JrqavfGnuUlvwvP2sh33K0wYwg3JNDmaiy0hzT/RPG1oG76HkolKJCsHknt/E/HH
gwzRRMCm1Acb25KoW7OCbyrQr3Z3X4VByTUnhU0mUtO2Zs9cOn81sXPmKZm6ALLk
+4hpKTebAgMBAAECggEADpKcthmiFSb0D0GjGu1Cswca94i6SVYUzZF6PfpHhYzM
N0rsEOSuE9oEoXBS4qL7ILK23VrKI5lr39NfrsZ47ToqvjJovUP4fbzFZal9AU5E
wFStxGk0EKxRSBj1wyKGW+xYaeG5mxxQ0/s6IZtQDGrnqrnq8n9oJCNRJtawja9t
ixbRNWU6XLt2pi94IMfXa7XE2pHXzoSpO9SR/pkmo8EsMzK5W4KfVUvZwkS4lF0b
Hq7T0nXEuL3ifcYwMNKSpUqM+If4I4s3GNBNeFUCqcJcFfkYglarrzbQVhYId23s
yiCjKX5p8Nh+A+9+nB0Am2fxtyR8pQqmbf3BBwQZjQKBgQDMH/Rc6zrUFY40xMNY
JDtmubGc5cHXRI7HwTwikSQnSCeahh1tUqN5rV3DIY+xt7UAymbdzh3oONfRZWoy
DOJgylu5MjNhaUP5Exys6Mq3VQaW0qARJ1mICa1mSea5DklMe7+2uysoyy4zufa8
mVK36j/QPnwew1/TmduiH3fVfwKBgQDA3GZbS22Ak2x5B2jSpUQ149AK4DfaDPoY
NmeFFviGrCoeW5AG813FXwDU6NUK7Bow7ZNRBpQGrdLC+lwPEL2TqFC1eRTLf2zk
ZwM0/fQR5yS6vLmPFrwNglc7LxKAd67vS70kOjRIno/dp6raFCV5/UmmfuGx43gl
xlM9K2lD5QKBgQCmO2OqhBpNexxrFs4qqp8BYjollupMH9XTESei0uZJYzZ1XcD7
NbBRuADCl0NJLF0oPqyU93Vdl2USbu+TwPBeeI1H/XzgWHR1k73nhlEICiMqkm6u
aYg9A/yFb6uIivzgX2raKgTU3NpMX6ZzIr29bvP259v2xY71aLf3iH7ziwKBgQCb
ICxMfo0jgHEdoHIWDMyitA0g0lzaTNnVI918VY+tc0mlhWyByrrACLx4hJbn5CTk
+hMmdy4VeTcvkYT+sS5rWFUiwrORQ3to89rGgwYQaGVItohiqZy1GQPlHOW644mX
/Mm0HAT17GQ3m6d3JgFG8A6PlzsehKKdb7qAVyyiaQKBgQCt771lXPJMSrb9fgv6
Cj+SyjQdBEGEul/HTBtO26W+16KFBwa/hSKHzIWC+IJ7vDywaendNuO2WYpLK0Pk
8cA900QESES6Xd09YPS5bL1kBn6XggpkkhqhfXJ0p1GXb4lVaf6mM/8q90/+YHi0
4kbKSDjptkQx4DEJC7n/tcCg2Q==
-----END PRIVATE KEY-----
"""

    private static let fixtureAnswer =
        "AQBzwcH0nh3bd39Erirem3QV5A5IzcBgwJR3w4lrmtOnwNeIHPQjU0ifmByzf1nlDU5dCR31W9U/TM7X0rTFxVMSnqWxEq6aJD9H" +
        "lDfsVm5OICKHynDIi7q7Lzh3xQ8/kFau2gDm33JnTj9S/CFjoicPhFno6/EzSAdd4T8ZV8X8/MyKSpSijiBprJjHnp+WZAabjT9U" +
        "Y1CBG42DBkMHDgt8DKYDuDfCxPyGski6p0kcG60ybf3BFO3syxN/AGRNAdvbqECqcuJ0v7IREGSj7CLb1qpQ6Nsw1i0c357mIUS1" +
        "LnDp2HC9tRcMKK9YNZa6HcjaAv/DPeJpw38uBlFZs/IhVtXjAye1ztyNEITN6JTV9GjeMKMt+L8veO0bQNQX7UwFQtsD05FeG+zw" +
        "IgfKnsRp3geSDWzO1jtZXxQqwII/koQptnZUVk0vQhjNrlStasIJDjCr/KxdC6In43dwT3z9RsvHriaOSTv7hH44acvzLrP2UkfX" +
        "9P4WXpoBVmLCV39XB6FVCNk="
}
