import { ArrowRight, EyeOff, Lock, ServerOff, UserX } from "lucide-react";
import { DownloadButtons } from "@/components/DownloadButtons";
import { Showcase } from "@/components/Showcase";
import { features, platforms, steps } from "@/content/features";
import { site } from "@/content/site";

const promises = [
  { icon: ServerOff, text: "No servers" },
  { icon: UserX, text: "No account" },
  { icon: EyeOff, text: "No ads or tracking" },
  { icon: Lock, text: "Encrypted end to end" },
];

export default function Home() {
  return (
    <main>
      <section className="hero">
        <div className="container hero-grid">
          <div>
            <span className="eyebrow">For Android, Mac and Windows</span>
            <h1>
              Android, <em>meet your computer.</em>
            </h1>
            <p className="lead">
              Texts, calls, notifications, files and photos from your phone, on your Mac or PC.
            </p>
            <DownloadButtons />
            <p className="hero-note">Free. No account.</p>
          </div>

          <div className="hero-visual" aria-hidden="true">
            <div className="gold-blob" />
            <img className="mac" src="/screens/mac-panel.png" alt="" />
            <img className="call" src="/screens/call-card.png" alt="" />
            <img className="phone" src="/screens/android-home.png" alt="" />
          </div>
        </div>
      </section>

      <section className="section" id="features">
        <div className="container">
          <div className="section-head">
            <span className="eyebrow">What it does</span>
            <h2>Put the phone down. Keep up anyway.</h2>
          </div>

          <div className="features">
            {features.map(({ icon: Icon, title, body }) => (
              <div className="feature" key={title}>
                <div className="feature-icon">
                  <Icon size={22} />
                </div>
                <h3>{title}</h3>
                <p>{body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="container">
        <Showcase
          eyebrow="Messages and calls"
          title="Answer from wherever you're sitting."
          body="Text from a proper Messages window. See who's calling and pick up."
          points={[
            "Reply to SMS from your keyboard",
            "Answer, decline or start calls",
            "Talk through your Mac's speakers and mic",
          ]}
          media={
            <div className="stack">
              <img src="/screens/call-card.png" alt="An incoming call card on the Mac with answer and decline buttons" />
              <img src="/screens/messages.png" alt="The Messages window on the Mac, choosing which phone to text from" />
            </div>
          }
        />

        <Showcase
          reverse
          eyebrow="FlyyDrop"
          title="Send it to anyone nearby. No pairing."
          body="Send photos and files to any phone or computer with Aproid on your Wi-Fi. They tap Accept."
          points={[
            "Phones, Macs and PCs",
            "Nothing arrives until accepted",
            "Open to everyone, for 10 minutes, or paired only",
          ]}
          media={<img className="bleed" src="/screens/flyydrop.png" alt="An Android phone being asked to accept three photos sent with FlyyDrop" />}
        />

        <Showcase
          gold
          eyebrow="All your devices"
          title="Two phones? Two computers? No problem."
          body="Each device gets its own card. Swipe between them."
          points={[
            "Pair as many as you want",
            "Calls and texts from the right phone",
            "Share files and the clipboard between computers",
          ]}
          media={<img className="tall" src="/screens/mac-panel.png" alt="The Aproid panel on a Mac with two phones paired" />}
        />

        <Showcase
          eyebrow="Screen mirroring"
          title="Your phone, in a window, with sound."
          body="Use any phone app with your mouse and keyboard."
          points={[
            "Smooth video, with sound",
            "Click, scroll and type",
            "Mac and Windows",
          ]}
          reverse
          media={<img className="tall" src="/screens/android-home.png" alt="Aproid on Android, showing a paired MacBook Pro" />}
        />
      </section>

      <section className="section" id="privacy">
        <div className="container">
          <div className="privacy-band">
            <div>
              <span className="eyebrow">Privacy</span>
              <h2>Your stuff stays yours.</h2>
              <p>Your devices talk straight to each other over your own network or Bluetooth. Nothing goes to a server.</p>
            </div>

            <div className="pills">
              {promises.map(({ icon: Icon, text }) => (
                <div className="pill" key={text}>
                  <Icon size={22} />
                  {text}
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      <section className="section" id="download">
        <div className="container">
          <div className="section-head">
            <span className="eyebrow">Get started</span>
            <h2>Up and running in a minute.</h2>
          </div>

          <div className="steps">
            {steps.map((step) => (
              <div className="step" key={step.title}>
                <h3>{step.title}</h3>
                <p>{step.body}</p>
              </div>
            ))}
          </div>

          <div className="platforms">
            {platforms.map((platform) => (
              <a className="platform" href={site.releases} key={platform.name}>
                <strong>{platform.name}</strong>
                <span>{platform.needs}</span>
                <span>{platform.detail}</span>
                <span className="platform-cta">
                  Download <ArrowRight size={16} />
                </span>
              </a>
            ))}
          </div>
        </div>
      </section>

      <section className="cta">
        <div className="container">
          <img src="/icon.svg" alt="" width={96} height={96} />
          <h2>Give it a try.</h2>
          <p className="lead">Free and open source.</p>
          <DownloadButtons />
        </div>
      </section>
    </main>
  );
}
