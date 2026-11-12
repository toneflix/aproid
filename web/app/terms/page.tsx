import type { Metadata } from "next";
import { LegalPage } from "@/components/LegalPage";
import { site } from "@/content/site";

export const metadata: Metadata = {
  title: "Terms of Use",
  description: "The terms for using the Aproid apps for Android, macOS and Windows.",
};

export default function TermsPage() {
  return (
    <LegalPage title="Terms of Use">
      <p>
        These terms apply to the Aproid apps for Android, macOS and Windows (&quot;Aproid&quot;), made by{" "}
        {site.legalEntity} (&quot;we&quot;, &quot;us&quot;). By installing or using Aproid you agree to them. If you do
        not agree, please do not use Aproid.
      </p>

      <h2>1. The software</h2>
      <p>
        Aproid is owned by {site.legalEntity}. We grant you a personal, non-transferable license to install and use
        the apps we publish, including through Google Play. You may not copy, modify, resell or redistribute them, or
        reverse engineer them except where the law allows it.
      </p>

      <h2>2. Using Aproid</h2>
      <ul>
        <li>Only pair devices that you own or are allowed to use.</li>
        <li>
          Do not use Aproid to access another person&apos;s messages, calls, notifications, location, photos or screen
          without their permission.
        </li>
        <li>Follow the laws that apply to you, including those on recording calls and sending messages.</li>
        <li>
          You are responsible for the content you send with Aproid and for any charges from your mobile carrier for
          texts and calls made through your phone.
        </li>
      </ul>

      <h2>3. Your data</h2>
      <p>
        Aproid moves information directly between your own devices. We do not receive it. Our{" "}
        <a href="/privacy">Privacy Policy</a> explains this in full.
      </p>

      <h2>4. Other apps and services</h2>
      <p>
        Aproid can work with KDE Connect and relies on your operating system, your network and services such as
        GitHub and map providers. We are not responsible for those, and their own terms apply.
      </p>

      <h2>5. Features that are still experimental</h2>
      <p>
        Some features, such as call audio on the Mac, are marked as experimental. They may not work on every device
        and may change or be removed.
      </p>

      <h2>6. No warranty</h2>
      <p>
        Aproid is provided &quot;as is&quot;, without warranties of any kind, express or implied, including fitness
        for a particular purpose and non-infringement. We do not promise that it will be uninterrupted, error free or
        compatible with every device. Keep your own backups of anything important before transferring it.
      </p>

      <h2>7. Limitation of liability</h2>
      <p>
        To the fullest extent the law allows, we are not liable for any indirect, incidental, special or consequential
        damages, or for any loss of data, messages, calls or profits, arising from your use of Aproid. Nothing in
        these terms limits liability that cannot be limited by law.
      </p>

      <h2>8. Ending use</h2>
      <p>You can stop using Aproid at any time by unpairing your devices and uninstalling the apps.</p>

      <h2>9. Changes</h2>
      <p>
        We may update these terms as Aproid changes. We will post the new version here with a new date. If you keep
        using Aproid after that, the new terms apply.
      </p>

      <h2>10. Governing law</h2>
      <p>These terms are governed by the laws of {site.jurisdiction}.</p>

      <h2>11. Contact</h2>
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
