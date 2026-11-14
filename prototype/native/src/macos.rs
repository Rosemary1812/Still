use std::{ffi::{CStr, c_char, c_void}, sync::mpsc};
type Reply = unsafe extern "C" fn(*const c_char, *const c_char, *mut c_void);
unsafe extern "C" { fn contactsheet_choose_photo(context: *mut c_void, reply: Reply); }
unsafe extern "C" fn reply(path: *const c_char, error: *const c_char, context: *mut c_void) {
    // Swift invokes this completion exactly once; this returns ownership of the sender.
    let sender = unsafe { Box::from_raw(context.cast::<mpsc::Sender<Result<String, String>>>()) };
    let result = if !path.is_null() {
        Ok(unsafe { CStr::from_ptr(path) }.to_string_lossy().into_owned())
    } else if !error.is_null() {
        Err(unsafe { CStr::from_ptr(error) }.to_string_lossy().into_owned())
    } else { Err("Photo bridge returned no result".into()) };
    let _ = sender.send(result);
}
pub async fn latest() -> Result<String, String> {
    let (sender, receiver) = mpsc::channel();
    unsafe { contactsheet_choose_photo(Box::into_raw(Box::new(sender)).cast(), reply); }
    loop {
        match receiver.try_recv() {
            Ok(result) => return result,
            Err(mpsc::TryRecvError::Disconnected) => return Err("Photo bridge disconnected".into()),
            Err(mpsc::TryRecvError::Empty) => nsh_core::prelude::timer(std::time::Duration::from_millis(50)).await,
        }
    }
}
