#!/bin/bash
# 文件路径：shell/custom-packages.sh
# 功能：第三方插件追加（开关联动）
# 联动变量：ENABLE_STORE / ENABLE_OC（由工作流 Enable integrations 步骤写入）

if [ "${ENABLE_STORE}" = "true" ]; then
    PACKAGES="$PACKAGES luci-app-store"
    echo "✅ 已追加 luci-app-store"
fi

if [ "${ENABLE_OC}" = "true" ]; then
    PACKAGES="$PACKAGES luci-app-openclash"
    echo "✅ 已追加 luci-app-openclash"
fi
