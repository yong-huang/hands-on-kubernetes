#!/usr/bin/env bash
# 从 api/proto 生成 Go / Python 桩代码（提交生成产物，构建环境零依赖）
set -euo pipefail
cd "$(dirname "$0")/.."

step() { echo "=====> [$1] $2"; }

# ---- Go：需要两个 protoc 插件，缺则装到 $(go env GOPATH)/bin ----
step "go" "生成 Go 桩到 api/gen/go/mart/v1/"
export PATH="$PATH:$(go env GOPATH)/bin"
command -v protoc-gen-go >/dev/null || go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
command -v protoc-gen-go-grpc >/dev/null || go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
protoc -I api/proto \
  --go_out=api/gen/go --go_opt=paths=source_relative \
  --go-grpc_out=api/gen/go --go-grpc_opt=paths=source_relative \
  api/proto/mart/v1/product.proto

# ---- Python：grpcio-tools 装到隔离目录，不污染全局 ----
step "python" "生成 Python 桩到 services/product/app/"
TOOLS_DIR=/tmp/mart-grpc-tools
if ! PYTHONPATH="$TOOLS_DIR" python3 -c "import grpc_tools" 2>/dev/null; then
    python3 -m pip install --quiet --target "$TOOLS_DIR" "grpcio-tools==1.66.2"
fi
PYTHONPATH="$TOOLS_DIR" python3 -m grpc_tools.protoc -I api/proto \
  --python_out=services/product/app --grpc_python_out=services/product/app \
  api/proto/mart/v1/product.proto
# 生成的 import 形如 `from mart.v1 import product_pb2`，补齐包结构
touch services/product/app/mart/__init__.py services/product/app/mart/v1/__init__.py

echo "生成完成："
ls -1 api/gen/go/mart/v1/ services/product/app/*pb2*.py
