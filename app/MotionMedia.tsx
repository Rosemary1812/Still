import { effect, signal, Text, Video, View, type ViewStyle } from "nsh";
import { Button } from "nsh/base";
import type { Photo } from "./DesktopState";

const frame: ViewStyle = { position: "absolute", top: 0, bottom: 0, left: 0, right: 0 };
const badge: ViewStyle = { backgroundColor: "rgba(18,18,18,0.78)", borderRadius: 12, paddingHorizontal: 8, paddingVertical: 4 };
const caption = { color: "#fff", fontSize: 11 };

function label(photo?: Photo) {
  if (photo?.kind === "live") return "实况";
  if (photo?.kind !== "video") return "";
  const seconds = Math.floor(photo.duration ?? 0);
  return seconds > 0 ? `视频 · ${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}` : "视频";
}

export function MediaBadge(p: { photo?: Photo }) {
  return <If when={label(p.photo)}><View style={{ ...badge, position: "absolute", left: 4, bottom: 4, pointerEvents: "none" }}>
    <Text style={caption}>{label(p.photo)}</Text>
  </View></If>;
}

type Slide = { playing: boolean; finish: (poster: string, failed: boolean) => void };

export function MotionMedia(p: { photo?: Photo; slide?: Slide }) {
  const items = () => p.photo && (p.photo.kind === "video" || p.photo.kind === "live") ? [p.photo] : [];
  return <Each of={items()} key={item => item.id}>{item => <MotionItem photo={item()} slide={p.slide} />}</Each>;
}

function MotionItem(p: { photo: Photo; slide?: Slide }) {
  const started = signal(false);
  const held = signal(false);
  const finished = signal(false);
  const failed = signal(false);
  const live = () => p.photo.kind === "live";
  const active = () => !failed() && (p.slide ? !finished() : live() ? held() : started());
  let previouslyPlaying = !!p.slide?.playing;
  effect(() => {
    const playing = !!p.slide?.playing;
    if (playing && !previouslyPlaying && !live()) {
      failed.set(false);
      finished.set(false);
    }
    previouslyPlaying = playing;
  });
  function end(error: boolean) {
    if (error) failed.set(true);
    if (p.slide) {
      finished.set(true);
      if (!live()) p.slide.finish(p.photo.url, error);
    } else {
      started.set(false);
      held.set(false);
    }
  }
  function start() {
    failed.set(false);
    if (live()) held.set(true);
    else started.set(true);
  }
  return <View style={{ ...frame, pointerEvents: "box-none" }}>
    <If when={active() && p.photo.videoUrl}><Video testID="media-player" src={p.photo.videoUrl ?? ""} paused={p.slide ? !p.slide.playing : false}
      controls={!p.slide && !live()} style={{ ...frame, width: "100%", height: "100%", objectFit: "contain", backgroundColor: "#151515" }}
      onEnd={() => end(false)} onError={() => end(true)} /></If>
    <If when={!p.slide && (live() || !started()) && p.photo.videoUrl}>
      <Button testID="media-play" accessibilityLabel={live() ? "按住播放实况照片" : "播放视频"}
        onPressIn={() => { if (live()) start(); }} onPressOut={() => { if (live()) held.set(false); }}
        onPress={e => { if (!live() || e.clickCount === 0) start(); }}
        style={{ ...frame, alignItems: "center", justifyContent: live() ? "flex-end" : "center", paddingBottom: live() ? 12 : 0 }}>
        <View style={badge}><Text style={caption}>{live() ? "按住播放实况" : "▶  播放视频"}</Text></View>
      </Button>
    </If>
    <If when={failed() || !p.photo.videoUrl}><View style={{ ...badge, position: "absolute", top: 8, left: 8, pointerEvents: "none" }}>
      <Text style={caption}>{live() ? "实况片段无法播放" : "视频无法播放"}</Text>
    </View></If>
  </View>;
}
