using Aproid.Core;

namespace Aproid.Core.Tests;

/// Mirrors LicenceTests.swift. The tokens were signed by the licence server's code with a test key.
public class LicenceTests
{
    private const string PublicKey = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEncVafPUhUOuV2pFFsl3AV3asVMwIby4RkyUx9aA4H6rua20jBexnHB4GmtFK2KBcQE01LOdbR00l6ttq4ep/ig==";
    private const string LicenceFixture = "eyJ2IjoxLCJraW5kIjoibGljZW5jZSIsIm1hY2hpbmUiOiJtMSIsImVtYWlsIjoiYnV5ZXJAZXhhbXBsZS5jb20iLCJpc3N1ZWQiOjEwMDAsInJlbmV3IjoyMDAwLCJleHBpcmVzIjozMDAwfQ.e6G63Vg1icZgrAkvoXYq0QMxJpBU4QGP0XMlmELrk-ITRSOjgGeIOjdzvGKebc33nWoBtOr0rJsZYpHSL0C14w";
    private const string TrialFixture = "eyJ2IjoxLCJraW5kIjoidHJpYWwiLCJtYWNoaW5lIjoibTEiLCJpc3N1ZWQiOjEwMDAsInJlbmV3Ijo1MDAwLCJleHBpcmVzIjo1MDAwfQ.p_7sfjcfFzFUMyBWR6VaSjy8ux7QFhPTc0EtkjZewOA8-iAMa-Kanv_SSsC8M8um3Nf86iZBUyq41CdmO1zikQ";

    private static readonly DateTimeOffset FirstLaunch = DateTimeOffset.FromUnixTimeSeconds(1000);

    [Fact]
    public void ReadsASignedToken()
    {
        var claims = LicenceToken.Verify(LicenceFixture, PublicKey);

        Assert.Equal(new LicenceClaims("licence", "m1", "buyer@example.com", 1000, 2000, 3000), claims);
    }

    [Fact]
    public void RefusesAChangedToken()
    {
        var trialBody = TrialFixture.Split('.')[0];
        var licenceSignature = LicenceFixture.Split('.')[1];

        Assert.Null(LicenceToken.Verify($"{trialBody}.{licenceSignature}", PublicKey));
        Assert.Null(LicenceToken.Verify("not a token", PublicKey));
    }

    [Fact]
    public void LicensedUntilItExpires()
    {
        var record = new LicenceRecord(LicenceFixture, null, FirstLaunch, null);

        Assert.Equal(new LicenceStatus.Licensed("buyer@example.com", false), Evaluate(record, 1500));
        Assert.Equal(new LicenceStatus.Licensed("buyer@example.com", true), Evaluate(record, 2500));
        Assert.Equal(new LicenceStatus.Locked(LicenceLock.Offline), Evaluate(record, 3000));
    }

    [Fact]
    public void TokenForAnotherComputerDoesNotCount()
    {
        var record = new LicenceRecord(LicenceFixture, TrialFixture, FirstLaunch, null);

        Assert.Equal(new LicenceStatus.Trial(LicenceRules.TrialDays), LicenceRules.Evaluate(record, "m2", PublicKey, DateTimeOffset.FromUnixTimeSeconds(1500)));
    }

    [Fact]
    public void TrialCountsDownThenLocks()
    {
        var record = new LicenceRecord(null, TrialFixture, FirstLaunch, null);

        Assert.Equal(new LicenceStatus.Trial(1), Evaluate(record, 4000));
        Assert.Equal(new LicenceStatus.Locked(LicenceLock.TrialOver), Evaluate(record, 5000));
    }

    [Fact]
    public void OfflineTrialRunsFromFirstLaunch()
    {
        var record = new LicenceRecord(null, null, FirstLaunch, null);

        Assert.Equal(new LicenceStatus.Trial(14), Evaluate(record, 1001));
        Assert.Equal(new LicenceStatus.Trial(1), Evaluate(record, 1000 + 13 * 86400 + 1));
        Assert.Equal(new LicenceStatus.Locked(LicenceLock.Offline), Evaluate(record, 1000 + 14 * 86400));
    }

    [Fact]
    public void ServerLockWinsOverTheTrial()
    {
        var record = new LicenceRecord(null, TrialFixture, FirstLaunch, LicenceLock.Removed);

        Assert.Equal(new LicenceStatus.Locked(LicenceLock.Removed), Evaluate(record, 1500));
    }

    [Fact]
    public void NoKeyMeansUnlimited()
    {
        Assert.Equal(new LicenceStatus.Unlimited(), LicenceRules.Evaluate(new LicenceRecord(null, null, FirstLaunch, null), "m1", null, DateTimeOffset.UnixEpoch));
    }

    [Fact]
    public void MachineIdIsAStableHash()
    {
        Assert.Equal(MachineId.From(" ABC "), MachineId.From("abc"));
        Assert.Equal("024012ba71e56454f1a305db046e8a33b08ad2127b0032cc61f97c4c34deb6a1", MachineId.From("abc"));
    }

    private static LicenceStatus Evaluate(LicenceRecord record, long seconds) =>
        LicenceRules.Evaluate(record, "m1", PublicKey, DateTimeOffset.FromUnixTimeSeconds(seconds));
}
