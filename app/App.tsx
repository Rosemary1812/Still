import { mount, platform } from "nsh";
import { DesktopApp } from "./Desktop";
import { MobileApp } from "./Mobile";

if (platform.os === "ios") mount(MobileApp);
else mount(DesktopApp);
