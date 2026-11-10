import { ArrowRight, EyeOff, Lock, ServerOff, UserX } from "lucide-react";
import { DownloadButtons } from "@/components/DownloadButtons";
import { Showcase } from "@/components/Showcase";
import { features, platforms, steps } from "@/content/features";
import { site } from "@/content/site";

const promises = [
  { icon: ServerOff, text: "No servers. Your devices talk straight to each other." },
  { icon: UserX, text: "No account, no sign-up, no email." },
  { icon: EyeOff, text: "No ads, no analytics, no tracking." },
  { icon: Lock, text: "Everything encrypted. Only devices you pair can connect." },
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
              Answer texts and calls, see your notifications and swap files and photos with your phone, all from
              your Mac or PC. It&apos;s free, and nothing leaves your own network.
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
          <p>iPhone owners have had this for years: their phone and their computer just work together.</p>
          <p>
            A text comes in and they answer it from the laptop. A photo goes from pocket to desktop in a second. If you
            carry an Android phone, you&apos;ve mostly had to do without. Aproid fixes that. Pair your phone once and
            it&apos;ll work with your computer like they came in the same box.
          </p>
        </div>
      </section>

      <section className="section" id="features">
        <div className="container">
          <div className="section-head">
            <span className="eyebrow">What it does</span>
            <h2>Put the phone down. Keep up anyway.</h2>
            <p className="lead">All the things you keep picking your phone up for, on the screen you&apos;re already looking at.</p>
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
          body="Your texts are in a proper Messages window. When a call comes in, you see who it is and pick up without digging through your bag."
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
          eyebrow="All your devices"
          title="Two phones? Two computers? No problem."
          body="Each phone or computer you pair gets its own card. Click or swipe between them and everything else switches with you."
          points={[
            "Pair as many phones and computers as you want",
            "Calls and texts always come from the right phone",
            "Pair your Mac and PC to share files and the clipboard",
          ]}
          media={<img className="tall" src="/screens/mac-panel.png" alt="The Aproid panel on a Mac with two phones paired" />}
        />

        <Showcase
          eyebrow="Screen mirroring"
          title="Your phone, in a window, with sound."
          body="Open any app on your phone and use it from your computer with your mouse and keyboard. Great for the apps that only live on your phone."
          points={[
            "Smooth video, with sound",
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
              <span className="eyebrow">Privacy</span>
              <h2>Your stuff stays yours.</h2>
              <p>
                There&apos;s no Aproid server for your data to go to. Your phone and your computer talk straight to each
                other over your own network or Bluetooth, and only after you&apos;ve paired them and checked the same
                code on both screens. Your texts, photos and notifications never leave your own devices.
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
          <p className="lead">It&apos;s free, it&apos;s open source, and it takes a minute to set up.</p>
          <DownloadButtons />
        </div>
      </section>
    </main>
  );
}
