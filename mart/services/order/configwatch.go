// 应用侧热加载（项目 3，Go 侧组件）。
// 关键点与 Python 侧一致：kubelet 用 ..data 符号链接原子换名更新挂载卷，
// 所以 fsnotify 必须监听**父目录**——监听文件本身会因 inode 换掉而静默失效。
package main

import (
	"encoding/json"
	"log"
	"os"
	"path/filepath"
	"sync"

	"github.com/fsnotify/fsnotify"
)

type HotConfig struct {
	path string
	mu   sync.RWMutex
	data map[string]any
}

func NewHotConfig(path string) *HotConfig {
	hc := &HotConfig{path: path, data: map[string]any{}}
	hc.reload()
	go hc.watch()
	return hc
}

func (hc *HotConfig) reload() {
	b, err := os.ReadFile(hc.path)
	if err != nil {
		return // 换名瞬间可能读不到，等下一个事件再补
	}
	var m map[string]any
	if err := json.Unmarshal(b, &m); err != nil {
		return
	}
	hc.mu.Lock()
	hc.data = m
	hc.mu.Unlock()
	log.Printf("hot config updated: %v", m)
}

func (hc *HotConfig) Snapshot() map[string]any {
	hc.mu.RLock()
	defer hc.mu.RUnlock()
	out := make(map[string]any, len(hc.data))
	for k, v := range hc.data {
		out[k] = v
	}
	return out
}

func (hc *HotConfig) watch() {
	w, err := fsnotify.NewWatcher()
	if err != nil {
		log.Printf("fsnotify create: %v", err)
		return
	}
	defer w.Close()
	dir := filepath.Dir(hc.path)
	if err := w.Add(dir); err != nil {
		// 本地开发没挂 ConfigMap 时目录不存在，降级为不监听
		log.Printf("fsnotify watch %s: %v (无挂载则忽略)", dir, err)
		return
	}
	for {
		select {
		case ev, ok := <-w.Events:
			if !ok {
				return
			}
			_ = ev // 任何目录事件都触发重读；JSON 解析失败自然丢弃
			hc.reload()
		case err, ok := <-w.Errors:
			if !ok {
				return
			}
			log.Printf("fsnotify error: %v", err)
		}
	}
}
