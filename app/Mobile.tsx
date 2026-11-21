import { importSummary } from "./MediaImport";
import { MediaBadge, MotionMedia } from "./MotionMedia";
import { Image, Scroll, Text, View, safeAreaInsets, signal, fontScale, screenReaderEnabled, announce } from "nsh";
import { Button, Input } from "nsh/base";
import { Photos } from "contactsheet/native";

type Page = "shelf" | "album" | "reader" | "note" | "create" | "rename" | "delete" | "remove";

function Action(props: { label: string; run: () => void; disabled?: boolean }) {
  return <Button accessibilityLabel={props.label} disabled={props.disabled} onPress={props.run}
    class="min-h-11 rounded-full bg-neutral-200 dark:bg-neutral-800 px-4 items-center justify-center">
    <Text class="text-neutral-900 dark:text-white">{props.label}</Text>
  </Button>;
}

export function MobileApp() {
  const safe = safeAreaInsets();
  const landscape = signal(false);
  const useList = () => landscape() || fontScale() >= 1.4 || screenReaderEnabled();
  const page = signal<Page>("shelf");
  const error = signal("");
  const busy = signal(false);
  const importNotice = signal("");
  const library = signal<ReturnType<typeof Photos.library>>({ albums: [], photos: [], viewMode: "cabinet" });
  const albumId = signal("");
  const photoId = signal("");
  const name = signal("");
  const title = signal("");
  const note = signal("");
  const album = () => library().albums.find(a => a.id === albumId()) ?? library().albums[0];
  const ids = () => album()?.photoIds ?? [];
  const photo = (id: string) => library().photos.find(p => p.id === id);
  const current = () => photo(photoId());
  const stack = () => {
    const albums = library().albums;
    const index = albums.findIndex(a => a.id === album()?.id);
    return Array.from({length: Math.min(6, albums.length)}, (_, depth) => ({
      album: albums[(index + depth) % albums.length], depth
    })).reverse();
  };
  async function perform(operation: () => void | Promise<void>) {
    if (busy()) return;
    busy.set(true);
    error.set("");
    try {
      await operation();
      library.set(Photos.library());
    } catch (cause) { const message = String(cause); error.set(message); announce(message); }
    finally { busy.set(false); }
  }
  async function addMedia(source: "files" | "photos") {
    importNotice.set("");
    await perform(async () => {
      const result = source === "files" ? await Photos.addFiles(albumId()) : await Photos.addApplePhotos(albumId());
      const message = importSummary(result);
      importNotice.set(message);
      if (message) announce(message);
    });
  }
  function stepAlbum(direction: number) {
    const albums = library().albums;
    const index = albums.findIndex(a => a.id === album()?.id);
    const next = albums[index + direction];
    if (next) albumId.set(next.id);
  }
  function stepPhoto(direction: number) {
    const next = ids()[ids().indexOf(photoId()) + direction];
    if (next) photoId.set(next);
  }
  function beginEdit() {
    title.set(current()?.title ?? "");
    note.set(current()?.description ?? "");
    page.set("note");
  }
  function back() {
    error.set("");
    switch (page()) {
      case "reader": case "rename": case "delete": page.set("album"); break;
      case "note": case "remove": page.set("reader"); break;
      default: page.set("shelf");
    }
  }
  async function saveName() {
    if (!name().trim()) return;
    if (page() === "create") {
      const id = await Photos.createAlbumFromPicker(name().trim());
      if (!id) return;
      openAlbum(id);
    } else {
      Photos.renameAlbum(albumId(), name().trim());
      page.set("album");
    }
  }
  function openAlbum(id: string) { importNotice.set(""); albumId.set(id); page.set("album"); error.set(""); }
  try { library.set(Photos.library()); } catch (cause) { error.set(String(cause)); }
  return <View class="flex-1 bg-white dark:bg-neutral-950" onLayout={e => landscape.set(e.bounds.size.width > e.bounds.size.height)} style={{
    paddingTop: safe().top, paddingBottom: safe().bottom, paddingLeft: safe().left + 14, paddingRight: safe().right + 14
  }}>
    <View class="flex-row items-center justify-between py-3">
      <If when={page() !== "shelf"} else={<Text class="text-3xl font-bold dark:text-white">Still</Text>}>
        <Action label="返回" run={back} disabled={busy()} />
      </If>
      <If when={page() === "shelf"}>
        <Action label="新建相册" run={() => { name.set(""); page.set("create"); }} />
      </If>
    </View>
    <If when={!!error()}><Text testID="mobile-error" class="text-red-600 py-2">{error()}</Text></If>
    <If when={busy()}><Text class="text-neutral-600 dark:text-neutral-200 py-1">正在处理…</Text></If>
    <If when={page() === "shelf"}>
      <If when={!!album()} else={<Text class="mt-12 text-center dark:text-white">新建相册，加入第一张照片。</Text>}>
        <If when={useList()} else={<View class="flex-1 items-center justify-center gap-4" testID="mobile-album-stack" onPanEnd={e => {
          if (Math.abs(e.translation.y) > 36) stepAlbum(e.translation.y < 0 ? 1 : -1);
        }}>
          <View class="w-full items-center justify-center" style={{ aspectRatio: 1 }}>
            <Each of={stack()} key={entry => entry.album.id}>{entry => <Button
              accessibilityLabel={`${entry().depth === 0 ? "打开" : "选择"}相册：${entry().album.name}`}
              class="absolute rounded-xl overflow-hidden bg-neutral-200" style={{
                width: `${78 - entry().depth * 5}%`, aspectRatio: 1, top: `${16 - entry().depth * 3}%`,
                boxShadow: "0 3px 10px rgba(0,0,0,0.22)"
              }} onPress={() => { if (entry().depth === 0) openAlbum(entry().album.id); else albumId.set(entry().album.id); }}>
              <If when={!!entry().album.coverId}><Image src={photo(entry().album.coverId ?? "")?.url ?? ""} style={{width:"100%",height:"100%",objectFit:"cover"}} /></If>
            </Button>}</Each>
          </View>
          <Text class="text-2xl font-bold dark:text-white">{album()?.name ?? ""}</Text>
          <Text class="text-neutral-500">{ids().length} 张照片</Text>
          <View class="flex-row gap-2">
            <Action label="上一本" run={() => stepAlbum(-1)} disabled={album()?.id === library().albums[0]?.id} />
            <Action label="打开" run={() => { albumId.set(album()?.id ?? ""); page.set("album"); }} />
            <Action label="下一本" run={() => stepAlbum(1)} disabled={album()?.id === library().albums[library().albums.length - 1]?.id} />
          </View>
        </View>}>
          <Scroll testID="mobile-album-list" class="flex-1"><View class="gap-2">
            <Each of={library().albums} key={item => item.id}>{item => <Button
              accessibilityLabel={`${item().name}，${item().photoIds.length} 张照片`} onPress={() => openAlbum(item().id)}
              class="min-h-11 flex-row items-center gap-3 py-2">
              <If when={!!item().coverId}><Image src={photo(item().coverId ?? "")?.url ?? ""} style={{width:56, height:56, objectFit:"cover",borderRadius:6}} /></If>
              <View class="flex-1"><Text class="text-lg dark:text-white">{item().name}</Text><Text class="text-neutral-500">{item().photoIds.length} 张照片</Text></View>
            </Button>}</Each>
          </View></Scroll>
        </If>
      </If>
    </If>
    <If when={page() === "album"}>
      <Scroll class="flex-1"><View class="gap-4">
        <Text class="text-2xl font-bold dark:text-white">{album()?.name ?? ""}</Text>
        <View class="flex-row flex-wrap gap-2">
          <Action label="从照片图库添加" disabled={busy()} run={() => void addMedia("photos")} />
          <Action label="从文件添加" disabled={busy()} run={() => void addMedia("files")} />
          <Action label="重命名" run={() => { name.set(album()?.name ?? ""); page.set("rename"); }} />
          <Action label="删除相册" run={() => page.set("delete")} />
        </View>
        <If when={importNotice()}><Text testID="mobile-import-result" class="text-neutral-600 dark:text-neutral-200">{importNotice()}</Text></If>
        <View class="flex-row flex-wrap gap-1">
          <Each of={ids()} key={id => id}>{id => <Button testID={`mobile-photo-${ids().indexOf(id()) + 1}`} accessibilityLabel={photo(id())?.title || `照片 ${ids().indexOf(id()) + 1}`} style={{width:landscape() ? "19%" : "32%",aspectRatio:1}} onPress={() => {photoId.set(id());page.set("reader");}}>
            <Image src={photo(id())?.url ?? ""} style={{width:"100%",height:"100%",objectFit:"cover"}} />
            <MediaBadge photo={photo(id())} />
          </Button>}</Each>
        </View>
      </View></Scroll>
    </If>
    <If when={page() === "reader"}>
      <View class="flex-1 gap-3" style={{flexDirection:landscape() ? "row" : "column"}}>
        <View class="flex-1" onPanEnd={e => {if (Math.abs(e.translation.x) > 32) stepPhoto(e.translation.x < 0 ? 1 : -1);}}>
          <Image src={current()?.url ?? ""} style={{width:"100%", height:"100%",objectFit:"contain"}} />
          <MotionMedia photo={current()} />
        </View>
        <Scroll style={{maxHeight:landscape() ? "100%" : "46%", ...(landscape() ? {width:"40%"} : {})}}><View class="gap-2">
        <Text class="text-xl dark:text-white">{current()?.title || `照片 ${ids().indexOf(photoId())+1} / ${ids().length}`}</Text>
        <Text class="dark:text-white">{current()?.description ?? ""}</Text>
        <View class="flex-row flex-wrap gap-2">
          <Action label="上一张" run={() => stepPhoto(-1)} disabled={photoId() === ids()[0]} />
          <Action label="下一张" run={() => stepPhoto(1)} disabled={photoId() === ids()[ids().length - 1]} />
          <Action label="编辑旁注" run={beginEdit} />
          <Action label={album()?.coverId === photoId() ? "当前封面" : "设为封面"} run={() => void perform(() => Photos.setCover(albumId(),photoId()))} />
          <Action label="移除照片" run={() => page.set("remove")} />
        </View></View></Scroll>
      </View>
    </If>
    <If when={page() === "create" || page() === "rename"}>
      <Scroll class="flex-1"><View class="gap-4"><Text class="text-xl dark:text-white">相册名称</Text>
        <Input testID="mobile-name" accessibilityLabel="相册名称" class="min-h-11 rounded-lg border border-neutral-400 px-3 dark:text-white" value={name()} onChange={e => name.set(e.value)} placeholder="相册名称" />
        <If when={page() === "create"}><Action label="创建空相册" disabled={busy() || !name().trim()} run={() => void perform(() => openAlbum(Photos.createAlbum(name().trim())))} /></If>
        <Action label={page() === "create" ? "创建并选择照片" : "保存名称"} run={() => void perform(saveName)} disabled={busy() || !name().trim()} />
      </View></Scroll>
    </If>
    <If when={page() === "note"}>
      <Scroll class="flex-1"><View class="gap-4">
        <Input testID="mobile-note-title" accessibilityLabel="照片标题" placeholder="标题" value={title()} onChange={e => title.set(e.value)} />
        <Input testID="mobile-note-body" accessibilityLabel="照片旁注" multiline placeholder="旁注" value={note()} onChange={e => note.set(e.value)} style={{minHeight:120}} />
        <Action label="保存旁注" run={() => void perform(() => {
          Photos.saveAnnotation(photoId(),title(),note(),current()?.date ?? "",current()?.location ?? "");page.set("reader");
        })} />
      </View></Scroll>
    </If>
    <If when={page() === "remove" || page() === "delete"}>
      <Scroll class="flex-1"><View class="gap-3">
        <Text class="text-lg dark:text-white">{page() === "remove" ? "从相册移除这张照片？" : "删除这本相册？"}</Text>
        <Action label="取消" run={back} />
        <Action label="确认" run={() => void perform(() => {
          if (page() === "remove") {Photos.removePhoto(albumId(),photoId());page.set("album");}
          else {Photos.deleteAlbum(albumId());albumId.set("");page.set("shelf");}
        })} />
      </View></Scroll>
    </If>
  </View>;
}
