import type { Metadata } from "next";
import { LegalPage } from "@/components/LegalPage";
import { site } from "@/content/site";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "How Aproid handles your data: on your devices, between your devices, and nowhere else.",
};

const permissions = [
  ["Notifications (notification access)", "Reads notifications on your phone so they can be shown, replied to, acted on or dismissed on your paired computer."],
  ["SMS (read and send)", "Shows your text conversations on your paired computer and sends the replies you write there."],
  ["Contacts", "Shows names instead of numbers for texts and calls on your paired computer."],
  ["Phone, call log and answering calls", "Tells your computer who is calling, lets you answer, decline or start calls from it, and shows recent callers."],
  ["Location, including in the background", "Only used when you ask a paired computer to find your phone. The phone sends its current location to that computer so it can be shown on a map."],
  ["Photos and videos", "Lets you browse recent photos and screenshots from your computer and copy the ones you pick."],
  ["Screen capture", "Streams your phone's screen to your paired computer when you start screen mirroring. Android asks for your consent every time."],
  ["Audio recording", "Captures the sound your phone is playing (not the microphone) while you mirror the screen, so you can hear it on your computer."],
  ["Accessibility service (\"Aproid Mac control\")", "Lets the mouse and keyboard on your paired computer tap, swipe, type and press Back, Home and Recents on your phone, only while you mirror the screen. To type, it reads the text field you have selected on the phone and nothing else on your screen. Aproid does not collect, store or share any personal data through it: your clicks and typing travel only between your own paired devices. It is off until you agree to Aproid's explanation and turn it on in Android's settings, and it is used for nothing else."],
  ["Bluetooth", "Finds your paired computer nearby and helps it connect when Wi-Fi is not available."],
  ["Wi-Fi, network and local hotspot", "Finds and connects to your paired devices on your local network, or through a temporary hotspot from your phone."],
  ["Files and clipboard", "Sends files, links and clipboard contents you choose to share to your paired devices, and saves the ones they send you."],
  ["Battery optimisation exemption and foreground service", "Keeps the connection alive in the background, shown as an ongoing notification."],
];

export default function PrivacyPage() {
  return (
    <LegalPage title="Privacy Policy">
      <div className="summary">
        <p>
          <strong>The short version:</strong> Aproid moves information between devices that you own and pair yourself.
          It does not send your data to us or to anyone else. We have no servers that receive it, no accounts, no
          advertising and no analytics.
        </p>
      </div>

      <p>
        This policy explains how the Aproid apps for Android, macOS and Windows (together, &quot;Aproid&quot;) handle
        information. Aproid is made by {site.legalEntity} (&quot;we&quot;, &quot;us&quot;). If you have a question,
        write to us at <a href={`mailto:${site.contactEmail}`}>{site.contactEmail}</a>.
      </p>

      <h2>1. How Aproid works</h2>
      <p>
        You install Aproid on your phone and on your computer, and pair them by confirming the same code on both
        screens. After that, the paired devices connect to each other directly over your local network, over Bluetooth,
        or through a hotspot from your phone. Every connection is encrypted with TLS, using a certificate each device
        creates for itself. Devices you have not paired cannot read anything Aproid sends.
      </p>
      <p>
        Nothing passes through servers run by us or by anyone else. Aproid does not need, and does not have, an
        account system.
      </p>

      <h2>2. Information Aproid accesses</h2>
      <p>
        Aproid only accesses information for the features you choose to use, and only after you grant the matching
        Android permission. You can turn any of them off at any time in Aproid or in your phone&apos;s settings.
      </p>
      <div className="table-scroll">
        <table>
          <thead>
            <tr>
              <th>Permission</th>
              <th>What it is used for</th>
            </tr>
          </thead>
          <tbody>
            {permissions.map(([name, use]) => (
              <tr key={name}>
                <td>{name}</td>
                <td>{use}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <h2>3. Where your information goes</h2>
      <p>
        Information accessed through these permissions is sent only to the devices you have paired with Aproid, over
        an encrypted connection, so they can show it to you. It is not sent to us, sold, shared with third parties, or
        used for advertising, profiling or any purpose other than the feature you are using.
      </p>
      <p>Aproid also speaks the open KDE Connect protocol, so you can pair it with KDE Connect on other devices. Anything you share with a device you pair is handled by the app on that device.</p>

      <h2>4. What is stored, and for how long</h2>
      <ul>
        <li>
          <strong>On every device:</strong> a device name and identifier, the encryption certificate, the list of
          devices you have paired, and your settings. These stay until you unpair a device or uninstall Aproid.
        </li>
        <li>
          <strong>Files and photos you send or download</strong> are saved where you can see them (for example your
          Downloads folder) and stay until you delete them.
        </li>
        <li>
          <strong>Notifications, messages, call details and location</strong> are shown on your computer while you
          use Aproid. The computer apps keep them in memory and in your operating system&apos;s notification centre,
          and do not upload them anywhere.
        </li>
      </ul>

      <h2>5. Services Aproid contacts on the internet</h2>
      <p>Aproid works without an internet connection. A few optional features contact outside services:</p>
      <ul>
        <li>
          <strong>Updates.</strong> The Mac and Windows apps check GitHub for new versions of Aproid. This request
          shares your IP address and app version with GitHub, as any download does. Android updates come through
          Google Play or the file you downloaded.
        </li>
        <li>
          <strong>Maps.</strong> When you look up your phone&apos;s location on your computer, the map is drawn by
          Apple Maps on a Mac and by OpenStreetMap on Windows. The map provider receives the area being shown so it
          can send map images. On Windows, opening the location in your browser uses Google Maps.
        </li>
        <li>
          <strong>Google Play.</strong> If you install Aproid from Google Play, Google handles the download and may
          collect information under its own privacy policy.
        </li>
      </ul>

      <h2>6. Children</h2>
      <p>
        Aproid is a general purpose tool and is not directed at children under 13. We do not knowingly collect
        information from anyone, including children.
      </p>

      <h2>7. Your choices</h2>
      <ul>
        <li>Revoke any permission in your phone&apos;s settings. The matching feature simply stops working.</li>
        <li>Unpair a device in Aproid to stop it from connecting and remove its certificate.</li>
        <li>Uninstall Aproid to remove everything it stored on that device.</li>
      </ul>
      <p>
        Because we do not receive or hold your personal data, there is nothing for us to export or delete on our side.
        If you have a question about your rights under laws such as the Nigeria Data Protection Act 2023, the GDPR or the CCPA, contact us and we will help.
      </p>

      <h2>8. Security</h2>
      <p>
        Connections between paired devices are encrypted and authenticated with each device&apos;s own certificate.
        Aproid is open source, so anyone can check how it handles data at{" "}
        <a href={site.github}>{site.github.replace("https://", "")}</a>.
      </p>

      <h2>9. Changes to this policy</h2>
      <p>
        If we change how Aproid handles information, we will update this page and the date at the top. Significant
        changes will also be mentioned in the app&apos;s release notes.
      </p>

      <h2>10. Contact</h2>
      <p>
        {site.legalEntity}
        <br />
        {site.legalAddress}
        <br />
        <a href={`mailto:${site.contactEmail}`}>{site.contactEmail}</a>
      </p>
    </LegalPage>
  );
}
