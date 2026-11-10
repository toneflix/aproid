import type { LucideIcon } from "lucide-react";
import {
  Bell,
  BatteryCharging,
  Clipboard,
  FolderUp,
  Images,
  Laptop,
  MessageSquare,
  MonitorSmartphone,
  Music,
  Phone,
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
    title: "Your notifications, where you're looking",
    body: "Phone notifications show up on your computer with the app's own icon. Reply to a chat, tap an action, or dismiss it and watch it clear on the phone too.",
  },
  {
    icon: MessageSquare,
    title: "Texts from your desk",
    body: "Read and send SMS in a proper Messages window, with every conversation right where you left it on the phone.",
  },
  {
    icon: Phone,
    title: "Calls without the scramble",
    body: "See who's calling and answer or decline from your computer. Start a call from your contacts. On a Mac, talk through the Mac's own speakers and mic.",
  },
  {
    icon: FolderUp,
    title: "Files without the cable",
    body: "Drag a file onto the panel, use the Share menu, or share from any app on your phone. Big videos pick up where they left off if the connection drops.",
  },
  {
    icon: MonitorSmartphone,
    title: "Your phone, on your screen",
    body: "Mirror the phone into a window, sound and all, and use it with your mouse and keyboard.",
  },
  {
    icon: Images,
    title: "Photos, the moment you take them",
    body: "Browse recent photos and screenshots from the computer and pull down the ones you want. On Windows they show up in File Explorer too.",
  },
  {
    icon: Clipboard,
    title: "One clipboard",
    body: "Copy on one device and paste on the other. Text, images and files.",
  },
  {
    icon: BatteryCharging,
    title: "The little things",
    body: "Battery at a glance with a low-battery heads up. Ring your phone when it's lost in the sofa, and see where it was last seen on a map.",
  },
  {
    icon: Music,
    title: "Media controls",
    body: "Pause, skip and change the volume of whatever is playing on the phone, or on your other computer.",
  },
  {
    icon: Smartphone,
    title: "More than one phone",
    body: "Pair a work phone and a personal one, or one phone with your Mac and your PC. Each gets its own card and you swipe between them.",
  },
  {
    icon: Laptop,
    title: "Computers, too",
    body: "Pair your Mac with your Windows PC to share files, links and the clipboard, check battery, ring a lost laptop and control the music.",
  },
  {
    icon: Wifi,
    title: "Works when the Wi-Fi doesn't",
    body: "Hotel network blocking devices? Aproid finds your phone over Bluetooth and connects through its own hotspot instead.",
  },
];

export const platforms = [
  { name: "Android", needs: "Android 8.0 or later", detail: "APK today, Google Play soon" },
  { name: "Mac", needs: "macOS 13 Ventura or later", detail: "Signed app that keeps itself up to date" },
  { name: "Windows", needs: "Windows 10 (1809) or later", detail: "Installer that keeps itself up to date" },
];

export const steps = [
  { title: "Install on both", body: "Get Aproid on your phone and on your Mac or PC." },
  { title: "Same network", body: "Join the same Wi-Fi, or your phone's hotspot." },
  { title: "Pair once", body: "Check the code matches on both screens and accept. That's it." },
];
