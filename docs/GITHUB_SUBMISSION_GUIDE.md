# GitHub 提交指南

## 推荐仓库设置

- Repository name：`pynq-ov5640-bird-deterrent`
- Description：`PYNQ-Z2 OV5640 intelligent visual bird deterrent system with Edge Impulse, external LED control and MCP4725 audio output`
- Visibility：`Public`
- Default branch：`main`
- License：仓库已包含 MIT License，不要再次自动生成许可证。

## 命令行上传

在本工程根目录打开终端，执行：

```bash
git init -b main
git add .
git commit -m "Release v2.0"
git remote add origin https://github.com/<GitHub用户名>/pynq-ov5640-bird-deterrent.git
git push -u origin main
```

如果网页端创建仓库时已经自动生成 README，请创建空仓库，或先拉取并合并后再推送。

## 上传后检查

1. 仓库首页显示 `Public`；
2. README 能正常显示；
3. `software/`、`fpga/`、`docs/` 均可浏览；
4. `software/model_v2_armv7_no_xnnpack.eim` 小于 GitHub 单文件 100 MB 限制；
5. 使用未登录或无痕浏览器打开仓库链接，确认无需权限即可访问；
6. 将仓库首页完整 URL 填入比赛平台的“Github链接输入”。

## 禁止上传

- GitHub 密码、Personal Access Token、SSH 私钥；
- 姓名、学校、指导教师等与作品无关的信息；
- Vivado 缓存、日志、综合中间文件和重复数据集。
