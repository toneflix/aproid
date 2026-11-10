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
    body: "Your phone's notifications pop up on your computer, app icon and all. Reply from your keyboard, or clear one and it's gone from the phone too.",
  },
  {
    icon: MessageSquare,
    title: "Texts",
    body: "Read and answer your SMS in a proper Messages window, with every conversation where you left it.",
  },
  {
    icon: Phone,
    title: "Calls",
    body: "See who's calling and pick up or decline from your computer. On a Mac you can even talk through its speakers and mic.",
  },
  {
    icon: FolderUp,
    title: "Files",
    body: "Drop a file on Aproid, use the Share menu, or share from any app on your phone. A big video that gets cut off carries on where it stopped.",
  },
  {
    icon: MonitorSmartphone,
    title: "Screen mirroring",
    body: "See your phone in a window, with sound, and use it with your mouse and keyboard.",
  },
  {
    icon: Images,
    title: "Photos",
    body: "Your latest photos and screenshots are right there on the computer. On Windows they show up in File Explorer too.",
  },
  {
    icon: Clipboard,
    title: "Clipboard",
    body: "Copy on one, paste on the other. Text, pictures, even files.",
  },
  {
    icon: MapPin,
    title: "Find your phone",
    body: "Lost it in the sofa again? Make it ring, even on silent. Not in the house? See where it was last on a map.",
  },
  {
    icon: Music,
    title: "Music and battery",
    body: "Play, pause and skip whatever's playing, keep an eye on the battery, and get a heads up when it's running low.",
  },
  {
    icon: Smartphone,
    title: "Two phones? Fine.",
    body: "Pair your work phone and your personal one, or one phone with your Mac and your PC. Swipe between them.",
  },
  {
    icon: Laptop,
    title: "Computer to computer",
    body: "Pair your computers with each other, Mac or PC, to pass files and links back and forth, share a clipboard and control the music on the other one.",
  },
  {
    icon: Wifi,
    title: "No Wi-Fi? Still works.",
    body: "On a hotel or café network that keeps devices apart, Aproid finds your phone over Bluetooth and uses its hotspot instead.",
  },
];

export const platforms = [
  { name: "Android", needs: "Android 8.0 or later", detail: "Google Play soon, or grab the APK now" },
  { name: "Mac", needs: "macOS 13 Ventura or later", detail: "Keeps itself up to date" },
  { name: "Windows", needs: "Windows 10 (1809) or later", detail: "Keeps itself up to date" },
];

export const steps = [
  { title: "Install it twice", body: "Once on your phone, once on your Mac or PC." },
  { title: "Same Wi-Fi", body: "Put both on the same Wi-Fi, or join your phone's hotspot." },
  { title: "Pair once", body: "Check the code matches on both screens and tap accept. Done." },
];
