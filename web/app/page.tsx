import { ArrowRight, EyeOff, Lock, ServerOff, UserX } from "lucide-react";
import { DownloadButtons } from "@/components/DownloadButtons";
import { Showcase } from "@/components/Showcase";
import { features, platforms, steps } from "@/content/features";
import { site } from "@/content/site";

const promises = [
  { icon: ServerOff, text: "No servers. Your devices talk to each other directly." },
  { icon: UserX, text: "No accounts, no sign-up, no email address." },
  { icon: EyeOff, text: "No ads, no analytics, no tracking." },
  { icon: Lock, text: "Every connection encrypted, every device paired by you." },
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
              Texts, calls, notifications, photos and files from your phone, right on your Mac or PC. Free, open
              source, and it never leaves your home network.
            </p>
            <DownloadButtons />
            <p className="hero-note">Free forever. No account needed.</p>
          </div>

          <div className="hero-visual" aria-hidden="true">
            <div className="gold-blob" />
            <img className="mac" src="/screens/mac-panel.png" alt="" />
            <img className="call" src="/screens/call-card.png" alt="" />
            <img className="phone" src="/screens/android-home.png" alt="" />
          </div>
        </div>
      </section>

      <section className="story">
        <div className="container">
          <p>iPhone owners get a quiet little luxury: their phone and their computer just work together.</p>
          <p>
            A text arrives and they answer it from the laptop. A photo goes from pocket to desktop in a second. If you
            carry an Android phone, you&apos;ve mostly had to go without. Aproid is our answer to that. Pair your phone
            once, and from then on it behaves like it was made for your computer.
          </p>
        </div>
      </section>

      <section className="section" id="features">
        <div className="container">
          <div className="section-head">
            <span className="eyebrow">Everything in one place</span>
            <h2>Put the phone down. Keep up anyway.</h2>
            <p className="lead">Everything your phone does best, without reaching for it every five minutes.</p>
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
          body="Your conversations sit in a proper Messages window, and an incoming call slides in with the caller's name so you can answer or decline without hunting for the phone."
          points={[
            "Read and reply to SMS from your keyboard",
            "Answer, decline or start calls",
            "On a Mac, talk through the Mac's speakers and mic",
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
          gold
          eyebrow="One home for every device"
          title="Two phones? Two computers? No problem."
          body="Aproid keeps a card for each device you pair. Swipe or click between them, and every window follows along."
          points={[
            "Pair as many phones and computers as you like",
            "Calls and texts always come from the right phone",
            "Pair your Mac and PC to share files and the clipboard",
          ]}
          media={<img className="tall" src="/screens/mac-panel.png" alt="The Aproid panel on a Mac with two phones paired" />}
        />

        <Showcase
          eyebrow="Screen mirroring"
          title="Your phone, in a window, with sound."
          body="Open any phone app on your computer and use it with your mouse and keyboard. Great for the apps that only live on your phone."
          points={[
            "Smooth video with the phone's own sound",
            "Click, scroll and type straight into the phone",
            "Works on both Mac and Windows",
          ]}
          media={<img className="tall" src="/screens/android-home.png" alt="Aproid on Android, showing a paired MacBook Pro" />}
        />
      </section>

      <section className="section" id="privacy">
        <div className="container">
          <div className="privacy-band">
            <div>
              <span className="eyebrow">Private by design</span>
              <h2>Your stuff stays between your devices.</h2>
              <p>
                Aproid has nowhere else to send it. Your phone and your computer talk directly over your local network
                or Bluetooth, and only after you&apos;ve paired them and checked the same code on both screens. Your
                messages, photos and notifications never touch our servers, because we don&apos;t have any.
              </p>
              <p>
                It also speaks the KDE Connect protocol, so it gets along with KDE Connect on Linux and other devices.
              </p>
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
            <h2>Set up in under a minute.</h2>
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
          <h2>Your phone has been waiting for this.</h2>
          <p className="lead">Free, open source and made with care for people who love their Android phones.</p>
          <DownloadButtons />
        </div>
      </section>
    </main>
  );
}
