// ISO base media containers (MP4/M4V and QuickTime). Inspect track headers
// without reading mdat payloads, which can be several gigabytes.
use std::fs::File;
use std::io::{self, Read, Seek, SeekFrom};

struct Atom {
    kind: [u8; 4],
    data: u64,
    end: u64,
}

fn children(
    file: &mut File,
    start: u64,
    end: u64,
    mut visit: impl FnMut(&mut File, Atom) -> io::Result<()>,
) -> io::Result<()> {
    let mut offset = start;
    while offset < end {
        file.seek(SeekFrom::Start(offset))?;
        let mut header = [0u8; 8];
        file.read_exact(&mut header)?;
        let mut data = offset + 8;
        let size = match u32::from_be_bytes(header[..4].try_into().unwrap()) {
            0 => end - offset,
            1 => {
                let mut extended = [0; 8];
                file.read_exact(&mut extended)?;
                data += 8;
                u64::from_be_bytes(extended)
            }
            size => u64::from(size),
        };
        let next = offset
            .checked_add(size)
            .filter(|&n| data <= n && n <= end)
            .ok_or(io::ErrorKind::InvalidData)?;
        visit(
            file,
            Atom {
                kind: header[4..].try_into().unwrap(),
                data,
                end: next,
            },
        )?;
        offset = next;
    }
    Ok(())
}

pub(super) fn inspect(file: &mut File) -> io::Result<Option<f64>> {
    let mut video = false;
    let mut payload = false;
    let mut duration = None;
    children(file, 0, file.metadata()?.len(), |file, atom| {
        if &atom.kind == b"mdat" && atom.end > atom.data {
            payload = true;
        } else if &atom.kind == b"moov" {
            children(file, atom.data, atom.end, |file, atom| {
                if &atom.kind == b"trak" {
                    children(file, atom.data, atom.end, |file, atom| {
                        if &atom.kind == b"mdia" {
                            children(file, atom.data, atom.end, |file, atom| {
                                if &atom.kind == b"hdlr" && atom.end - atom.data >= 12 {
                                    file.seek(SeekFrom::Start(atom.data + 8))?;
                                    let mut handler = [0; 4];
                                    file.read_exact(&mut handler)?;
                                    video |= &handler == b"vide";
                                }
                                Ok(())
                            })?;
                        }
                        Ok(())
                    })?;
                } else if &atom.kind == b"mvhd" && atom.end - atom.data >= 20 {
                    let mut header = [0; 32];
                    let count = (atom.end - atom.data).min(32) as usize;
                    file.read_exact(&mut header[..count])?;
                    let values = match header[0] {
                        0 => {
                            let ticks = u32::from_be_bytes(header[16..20].try_into().unwrap());
                            (ticks != u32::MAX).then_some((12, u64::from(ticks)))
                        }
                        1 if count == 32 => {
                            let ticks = u64::from_be_bytes(header[24..32].try_into().unwrap());
                            (ticks != u64::MAX).then_some((20, ticks))
                        }
                        _ => None,
                    };
                    if let Some((index, ticks)) = values {
                        let scale =
                            u32::from_be_bytes(header[index..index + 4].try_into().unwrap());
                        if scale > 0 && ticks > 0 {
                            duration = Some(ticks as f64 / f64::from(scale));
                        }
                    }
                }
                Ok(())
            })?;
        }
        Ok(())
    })?;
    if video && payload {
        Ok(duration)
    } else {
        Err(io::ErrorKind::InvalidData.into())
    }
}
