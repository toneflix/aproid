using System.Buffers.Binary;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Text.Json.Nodes;
using FlyyLink.Core;

namespace FlyyLink.Core.Tests;

/// Mirrors GoogleCastTests.swift and GoogleCastTest.kt.
public class GoogleCastTests
{
    private const string PingHex =
        "0800120873656e6465722d301a0a72656365697665722d30222775726e3a782d636173743a636f6d2e676f6f676c652e636173742e74702e6865617274626561742800320f7b2274797065223a2250494e47227d";

    // One answer from a Cast TV: a PTR to its instance, then TXT, SRV and A records, with compressed names.
    private const string AnswerHex =
        "0000840000000001000000030b5f676f6f676c6563617374045f746370056c6f63616c00000c000100000078001e1b416e64726f69642d54562d31613262336334643565366637613862c00cc02e0010800100001194003e1369643d316132623363346435653666376138620f6d643d4869536d617274545620413411666e3d4c6976696e6720526f6f6d2054560763613d32303533c02e00218001000000780016000000001f49083161326233633464056c6f63616c00c0a800018001000000780004c0a8011e";

    [Fact]
    public void EncodesCastMessages()
    {
        var message = new CastMessage(GoogleCast.Sender, GoogleCast.Receiver, GoogleCast.Heartbeat, """{"type":"PING"}""");

        Assert.Equal(PingHex, Convert.ToHexString(message.Encode()).ToLowerInvariant());
        Assert.Equal(message, CastMessage.Decode(Convert.FromHexString(PingHex)));
    }

    [Fact]
    public void IgnoresBrokenCastMessages()
    {
        Assert.Null(CastMessage.Decode(Convert.FromHexString(PingHex)[..20]));
        Assert.Null(CastMessage.Decode([0x08, 0x00]));
    }

    [Fact]
    public void MdnsQueryAsksForCastTvs()
    {
        Assert.Equal("0000000000010000000000000b5f676f6f676c6563617374045f746370056c6f63616c00000c8001", Convert.ToHexString(Mdns.Query()).ToLowerInvariant());
    }

    [Fact]
    public void ReadsCastTvsFromMdnsAnswers()
    {
        var tvs = Mdns.CastTvs(Mdns.Parse(Convert.FromHexString(AnswerHex)), sender: "192.168.1.99");

        Assert.Equal([new TvRenderer("cast:1a2b3c4d5e6f7a8b", "Living Room TV", Cast: new CastEndpoint("192.168.1.30", 8009))], tvs);
        Assert.Equal("192.168.1.30", tvs.Single().Host);
    }

    [Fact]
    public void IgnoresMdnsQuestions()
    {
        Assert.Empty(Mdns.Parse(Mdns.Query()));
        Assert.Empty(Mdns.Parse([1, 2, 3]));
    }

    [Fact]
    public void LoadsMediaOnTheDefaultReceiver()
    {
        var load = GoogleCast.Parse(GoogleCast.Load(7, "http://192.168.1.5:4000/t/song.mp3", "Song", "audio/mpeg").ToJsonString())!;
        var media = load["media"]!.AsObject();

        Assert.Equal("LOAD", GoogleCast.Type(load));
        Assert.Equal(7, GoogleCast.RequestId(load));
        Assert.True(load["autoplay"]!.GetValue<bool>());
        Assert.Equal("http://192.168.1.5:4000/t/song.mp3", media["contentId"]!.GetValue<string>());
        Assert.Equal("audio/mpeg", media["contentType"]!.GetValue<string>());
        Assert.Equal(3, media["metadata"]!["metadataType"]!.GetValue<int>());
        Assert.Equal("Song", media["metadata"]!["title"]!.GetValue<string>());
        Assert.Equal("CC1AD845", GoogleCast.Launch(1)["appId"]!.GetValue<string>());
        Assert.Equal(12.5, GoogleCast.Seek(2, 3, 12_500)["currentTime"]!.GetValue<double>());
    }

    [Fact]
    public void ReadsMediaStatus()
    {
        var status = GoogleCast.Parse("""{"type":"MEDIA_STATUS","requestId":4,"status":[{"mediaSessionId":3,"playerState":"PAUSED","currentTime":12.5,"media":{"duration":60}}]}""")!;

        Assert.Equal(new CastMedia(3, CastState.Paused, new CastPosition(12_500, 60_000)), GoogleCast.MediaOf(status));
        Assert.Equal(new CastMedia(null, CastState.Stopped, null), GoogleCast.MediaOf(GoogleCast.Parse("""{"type":"MEDIA_STATUS","status":[]}""")!));
        Assert.Equal(CastState.Loading, GoogleCast.State("BUFFERING"));
        Assert.Null(GoogleCast.MediaOf(GoogleCast.Parse("""{"type":"RECEIVER_STATUS"}""")!));
    }

    [Fact]
    public void ReadsTheRunningMediaReceiver()
    {
        var status = GoogleCast.Parse(
            """{"type":"RECEIVER_STATUS","requestId":1,"status":{"volume":{"level":0.35},"applications":[""" +
            """{"appId":"E8C28D3C","sessionId":"other","transportId":"other-1"},""" +
            """{"appId":"CC1AD845","sessionId":"abc","transportId":"web-5"}]}}""")!;

        Assert.Equal(new CastApp("abc", "web-5"), GoogleCast.MediaApp(status));
        Assert.Equal(35, GoogleCast.Volume(status));
        Assert.Null(GoogleCast.MediaApp(GoogleCast.Parse("""{"type":"RECEIVER_STATUS","status":{"applications":[]}}""")!));
    }

    [Fact]
    public void PrefersCastWhenATvAnswersBothWays()
    {
        var castTv = new TvRenderer("cast:1", "Living Room TV", Cast: new CastEndpoint("192.168.1.30"));
        var sameTv = new TvRenderer("uuid:a", "Hisense DMR", "http://192.168.1.30:9197/av");
        var other = new TvRenderer("uuid:b", "bedroom", "http://192.168.1.31/av");

        Assert.Equal([other, castTv], TvFinder.Merge([sameTv, other], [castTv]));
    }

    [Fact]
    public async Task PlaysAndControlsOnACastTv()
    {
        var certificate = DeviceCertificate.Generate("cast-tv").Certificate;
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        var received = new List<string>();

        var fake = Task.Run(async () =>
        {
            using var client = await listener.AcceptTcpClientAsync();
            await using var stream = new SslStream(client.GetStream());
            await stream.AuthenticateAsServerAsync(certificate);

            var state = "PLAYING";
            var time = 0.0;
            var head = new byte[4];

            async Task Reply(CastMessage to, string payload)
            {
                var bytes = new CastMessage(to.Destination, to.Source, to.Namespace, payload).Encode();
                var frame = new byte[4 + bytes.Length];
                BinaryPrimitives.WriteInt32BigEndian(frame, bytes.Length);
                bytes.CopyTo(frame, 4);
                await stream.WriteAsync(frame);
            }

            while (true)
            {
                try { await stream.ReadExactlyAsync(head); } catch (Exception e) when (e is IOException or ObjectDisposedException) { return; }

                var body = new byte[BinaryPrimitives.ReadInt32BigEndian(head)];
                await stream.ReadExactlyAsync(body);

                var message = CastMessage.Decode(body)!;
                var json = GoogleCast.Parse(message.Payload)!;
                var type = GoogleCast.Type(json)!;
                var id = GoogleCast.RequestId(json);
                if (type == "PING") continue;

                lock (received) received.Add(type);
                switch (type)
                {
                    case "LAUNCH":
                        await Reply(message, $$$"""{"type":"RECEIVER_STATUS","requestId":{{{id}}},"status":{"applications":[{"appId":"CC1AD845","sessionId":"s1","transportId":"web-1"}]}}""");
                        break;
                    case "PAUSE":
                        state = "PAUSED";
                        break;
                    case "SEEK":
                        time = json["currentTime"]!.GetValue<double>();
                        break;
                    case "STOP":
                        state = "IDLE";
                        break;
                }

                if (message.Namespace == GoogleCast.Media)
                    await Reply(message, $$$"""{"type":"MEDIA_STATUS","requestId":{{{id}}},"status":[{"mediaSessionId":9,"playerState":"{{{state}}}","currentTime":{{{time.ToString(System.Globalization.CultureInfo.InvariantCulture)}}},"media":{"duration":120}}]}""");
                else if (type == "STOP")
                    await Reply(message, $$$"""{"type":"RECEIVER_STATUS","requestId":{{{id}}},"status":{"applications":[]}}""");
            }
        });

        try
        {
            var player = new TvPlayer(new TvRenderer("cast:1", "TV", Cast: new CastEndpoint("127.0.0.1", port)));

            await player.PlayAsync("http://127.0.0.1/t/clip.mp4", "Clip", "video/mp4");
            await player.PauseAsync();
            await player.SeekAsync(30_000);

            Assert.Equal(CastState.Paused, await player.StateAsync());
            Assert.Equal(new CastPosition(30_000, 120_000), await player.PositionAsync());

            await player.StopAsync();
            await fake;

            Assert.Equal(["CONNECT", "LAUNCH", "CONNECT", "LOAD", "PAUSE", "SEEK", "GET_STATUS", "GET_STATUS", "STOP", "STOP"], received);
            Assert.Equal(CastState.Stopped, await player.StateAsync());
        }
        finally
        {
            listener.Stop();
        }
    }
}
