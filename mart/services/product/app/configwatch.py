"""应用侧热加载（项目 3）。

kubelet 把 ConfigMap/Secret 挂进容器时用 `..data` 符号链接原子换名来更新，
所以监听对象必须是**父目录**而不是文件本身——文件 inode 会整个换掉，
监听文件的 watcher 会静默失效。这是热加载最大的坑。
"""
import json
import logging
import os
import threading

log = logging.getLogger("configwatch")


def _ensure_file(path, content):
    """无挂载的本地/测试环境写默认值；只读或无权限时静默降级"""
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if not os.path.exists(path):
            with open(path, "w") as f:
                f.write(content)
    except OSError:
        pass


class HotConfig:
    """watch 一个 JSON 配置文件，内容变更后线程安全地切换内存态"""

    def __init__(self, path, default=None, on_change=None):
        self.path = path
        self.on_change = on_change
        self._lock = threading.Lock()
        self._state = dict(default or {})
        _ensure_file(path, json.dumps(self._state))
        self.reload()
        self._watch()

    def reload(self, *_args):
        try:
            with open(self.path) as f:
                data = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            return  # 换名瞬间可能读到半态，丢掉这次，下个事件再补
        with self._lock:
            changed = data != self._state
            if changed:
                self._state = data
        if changed:
            log.info("hot config updated: %s", data)
            if self.on_change:
                self.on_change(data)

    def snapshot(self):
        with self._lock:
            return dict(self._state)

    def _watch(self):
        # 用 PollingObserver 而不是默认的 inotify Observer：kubelet 对
        # ConfigMap/Secret 卷用 ..data 符号链接原子换名，inotify 语义在
        # 这类卷上既不可靠也有坑（实测集群里内存线性增长直至 OOM），
        # stat 轮询 2s 一次最稳，远快于 kubelet ~1min 的同步周期
        from watchdog.observers.polling import PollingObserver
        from watchdog.events import FileSystemEventHandler

        outer = self

        class Handler(FileSystemEventHandler):
            def on_any_event(self, event):
                outer.reload()

        obs = PollingObserver(timeout=2)
        obs.schedule(Handler(), os.path.dirname(self.path), recursive=True)
        obs.daemon = True
        obs.start()


class FileSecretWatcher:
    """watch 一个纯文本 secret 文件，变更即回调（这里模拟用新密码重连数据库）"""

    def __init__(self, path, on_change):
        self.path = path
        self.on_change = on_change
        _ensure_file(path, "changeme")
        self._value = self._read()
        try:
            self._watch()
        except Exception as e:  # noqa: BLE001
            log.warning("secret watch disabled: %s", e)

    def _read(self):
        try:
            with open(self.path) as f:
                return f.read().strip()
        except FileNotFoundError:
            return ""

    def value(self):
        return self._value

    def _changed(self):
        v = self._read()
        if v and v != self._value:
            self._value = v
            log.info("secret rotated: reconnected with new password (len=%d)", len(v))
            self.on_change(v)

    def _watch(self):
        from watchdog.observers.polling import PollingObserver
        from watchdog.events import FileSystemEventHandler

        outer = self

        class Handler(FileSystemEventHandler):
            def on_any_event(self, event):
                outer._changed()

        obs = PollingObserver(timeout=2)
        obs.schedule(Handler(), os.path.dirname(self.path), recursive=True)
        obs.daemon = True
        obs.start()
