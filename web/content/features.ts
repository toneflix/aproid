import type { LucideIcon } from "lucide-react";
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
    body: "Reply from your keyboard. Clear one and it's gone from the phone too.",
  },
  {
    icon: MessageSquare,
    title: "Texts",
    body: "Read and answer SMS in a proper Messages window.",
  },
  {
    icon: Phone,
    title: "Calls",
    body: "Pick up or decline from your computer. On a Mac, talk through it too.",
  },
  {
    icon: FolderUp,
    title: "Files",
    body: "Drop, or share from any app. Big transfers resume if cut off.",
  },
  {
    icon: Radar,
    title: "FlyyDrop",
    body: "Send to anyone nearby with Aproid, no pairing. They tap Accept.",
  },
  {
    icon: MonitorSmartphone,
    title: "Screen mirroring",
    body: "Your phone in a window, with sound, mouse and keyboard.",
  },
  {
    icon: Images,
    title: "Photos",
    body: "Your latest photos and screenshots, on your computer. In File Explorer on Windows.",
  },
  {
    icon: Clipboard,
    title: "Clipboard",
    body: "Copy on one, paste on the other. Text, pictures and files.",
  },
  {
    icon: MapPin,
    title: "Find your phone",
    body: "Ring it, even on silent, or see it on a map.",
  },
  {
    icon: Music,
    title: "Music and battery",
    body: "Control what's playing and see the battery level.",
  },
  {
    icon: Smartphone,
    title: "Two phones? Fine.",
    body: "Pair several phones and computers. Swipe between them.",
  },
  {
    icon: Laptop,
    title: "Computer to computer",
    body: "Pair your Macs and PCs to share files, links, clipboard and music controls.",
  },
  {
    icon: Wifi,
    title: "No Wi-Fi? Still works.",
    body: "Aproid connects over Bluetooth and your phone's hotspot.",
  },
];

export const platforms = [
  { name: "Android", needs: "Android 8.0 or later", detail: "APK now, Google Play soon" },
  { name: "Mac", needs: "macOS 13 Ventura or later", detail: "Updates itself" },
  { name: "Windows", needs: "Windows 10 (1809) or later", detail: "Updates itself" },
];

export const steps = [
  { title: "Install", body: "On your phone and your computer." },
  { title: "Same Wi-Fi", body: "Or join your phone's hotspot." },
  { title: "Pair once", body: "Check the code matches and accept." },
];
