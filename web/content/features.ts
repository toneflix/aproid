import type { LucideIcon } from "lucide-react";
import { site } from "./site";
import {
  Bell,
  MapPin,
  Clipboard,
  FolderUp,
  Images,
  Laptop,
  MessageSquare,
  MonitorSmartphone,
  Music,
  Phone,
  Radar,
  Smartphone,
  Wifi,
} from "lucide-react";

export type Feature = {
  icon: LucideIcon;
  title: string;
  body: string;
};

export const features: Feature[] = [
  {
    icon: Bell,
    title: "Notifications",
    body: "Reply from your keyboard.",
  },
  {
    icon: MessageSquare,
    title: "Texts",
    body: "Read and reply.",
  },
  {
    icon: Phone,
    title: "Calls",
    body: "Answer on your computer.",
  },
  {
    icon: FolderUp,
    title: "Files",
    body: "Any size, from any app.",
  },
  {
    icon: Radar,
    title: "FlyyDrop",
    body: "Send to anyone nearby.",
  },
  {
    icon: MonitorSmartphone,
    title: "Screen mirroring",
    body: "Use your phone from your computer.",
  },
  {
    icon: Images,
    title: "Photos",
    body: "Your latest shots, on your computer.",
  },
  {
    icon: Clipboard,
    title: "Clipboard",
    body: "Copy on one, paste on the other.",
  },
  {
    icon: MapPin,
    title: "Find your phone",
    body: "Ring it, even on silent.",
  },
  {
    icon: Music,
    title: "Music and battery",
    body: "Play, pause, skip, and check the battery.",
  },
  {
    icon: Smartphone,
    title: "Several phones",
    body: "Pair as many as you like.",
  },
  {
    icon: Laptop,
    title: "Computer to computer",
    body: "Share files and the clipboard between Macs and PCs.",
  },
  {
    icon: Wifi,
    title: "No Wi-Fi? Still works.",
    body: "Connects through your phone's hotspot.",
  },
];

export const platforms = [
  { name: "Android", slug: "android", needs: "Android 8.0 or later", detail: "Free" },
  { name: "Mac", slug: "mac", needs: "macOS 13 Ventura or later", detail: `${site.trialDays} days free, then pay once` },
  { name: "Windows", slug: "windows", needs: "Windows 10 (1809) or later", detail: `${site.trialDays} days free, then pay once` },
];

export const steps = [
  { title: "Install", body: "Phone and computer." },
  { title: "Same Wi-Fi", body: "Or join your phone's hotspot." },
  { title: "Pair once", body: "Check the code matches." },
];
