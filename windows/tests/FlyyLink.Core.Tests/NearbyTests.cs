using System.Security.Cryptography;
using System.Text;
using FlyyLink.Core;

namespace FlyyLink.Core.Tests;

/// Mirrors NearbyTests.swift: the answer here was sealed by the Kotlin side, and every implementation opens the same bytes.
public class NearbyTests
{
    private static readonly Nearby.Answer Expected = new("a1b2c3d4e5f60718293a4b5c6d7e8f90", ["192.168.43.1"], 1716);

    [Fact]
    public void RequestRoundTrips()
    {
        var request = new Nearby.Request("a1b2c3d4e5f60718293a4b5c6d7e8f90", Nearby.Want.Hotspot);

        Assert.Equal(request, Nearby.Request.FromBytes(request.Bytes()));
        Assert.Null(Nearby.Request.FromBytes(Encoding.UTF8.GetBytes("""{"id":"../x","want":"connect"}""")));
    }

    [Fact]
    public void OpensTheSharedFixture()
    {
        using var key = Key();

        Assert.Equal(Expected, Nearby.Open(Convert.FromBase64String(FixtureAnswer), key));
    }

    [Fact]
    public void RefusesAChangedAnswer()
    {
        using var key = Key();
        var sealedBytes = Convert.FromBase64String(FixtureAnswer);
        sealedBytes[^1] ^= 1;

        Assert.ThrowsAny<CryptographicException>(() => Nearby.Open(sealedBytes, key));
    }

    private static RSA Key()
    {
        var key = RSA.Create();
        key.ImportFromPem(FixtureKey);

        return key;
    }

    // A throwaway key made only for this test.
    private const string FixtureKey = """
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
""";

    private const string FixtureAnswer = "AQArbPlsvq+u5pCnKp3xbqn08vUTiyMKdHiHyc76dkfAf2YxNzrLsrKAAf1FZ8EtKMNvA/H7Qq7owg+AcWvGse9OFhR+iQGrCgFJMlOsz3LcjK8CNU4hneY/hqHcqyX+AknfOyUQiR2f520ed7r7sinSEffv39m10v5/WHnjzWLBT499Ri2PRThK2SMVUT5419DTMVTMsaOwREUDWTL3CwMq+FSBDcEN4x85UzK9hMBtMjtZepAZ6Czu4wk+AFTG3JYv6S5OpuIZDrlzggtxTLYm34Igf64vsuEDzAbvwS/VTSDSL82P65Qk/seQ5s76QUdLL3ZN1rVQejK7fBaD7qa6h8RxWNBotWuq5mUsDL5SF1zffkGcJid4U/5MHinleHVEQ61HjVvS2JKfS6eQ3sfIYwdYHtOCzdnwaDz1Nm/LFi+z6+Lpnt8S6OkqUs/eieaXfphAV8o+4eMw5xZ3jd8pjyw=";
}
