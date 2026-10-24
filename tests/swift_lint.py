"""Windows 上没有 swiftc，跑不了真正的编译。

这个脚本做力所能及的静态检查，专抓「编译器一定会报错」的低级问题：
- 括号 / 方括号 / 花括号不配对
- 字符串字面量没闭合（会让后面所有行都被吞进字符串里）
- 用了 iOS 17+ 才有的 API（deploymentTarget 是 16.0）
- 同一个 View 上挂了两个 .sheet
- 文件用了 UIKit / UserNotifications 类型却没 import

跑法：python tests/swift_lint.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "ScreenshotLedger"

# deploymentTarget = 16.0，这些是 iOS 17 才有的东西
IOS17_APIS = [
    "ContentUnavailableView",
    "onChange(of: .*), { _, ",
    ".scrollTargetBehavior",
    ".containerRelativeFrame",
    "Previewable",
    ".contentMargins",
    "@Observable",
    "SwiftData",
]

problems = []


def strip_strings_and_comments(code: str) -> str:
    """把字符串字面量和注释换成等长空白，这样括号匹配不会被内容干扰。"""
    out = []
    i = 0
    n = len(code)
    while i < n:
        ch = code[i]
        # 行注释
        if code.startswith("//", i):
            j = code.find("\n", i)
            j = n if j == -1 else j
            out.append(" " * (j - i))
            i = j
            continue
        # 块注释（Swift 支持嵌套）
        if code.startswith("/*", i):
            depth = 1
            j = i + 2
            while j < n and depth:
                if code.startswith("/*", j):
                    depth += 1
                    j += 2
                elif code.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            out.append(" " * (j - i))
            i = j
            continue
        # 三引号字符串
        if code.startswith('"""', i):
            j = code.find('"""', i + 3)
            j = n if j == -1 else j + 3
            out.append(" " * (j - i))
            i = j
            continue
        # 普通字符串（含 \\( 插值，插值里可能还有括号，这里保守处理：整体吞掉）
        if ch == '"':
            j = i + 1
            while j < n:
                if code[j] == "\\":
                    j += 2
                    continue
                if code[j] == '"':
                    j += 1
                    break
                if code[j] == "\n":
                    break
                j += 1
            out.append(" " * (j - i))
            i = j
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def check_brackets(path: Path, code: str):
    stripped = strip_strings_and_comments(code)
    pairs = {")": "(", "]": "[", "}": "{"}
    stack = []
    for lineno, line in enumerate(stripped.split("\n"), start=1):
        for ch in line:
            if ch in "([{":
                stack.append((ch, lineno))
            elif ch in ")]}":
                if not stack:
                    problems.append(f"{path.name}:{lineno} 多出来的 {ch}")
                    continue
                opener, opened_at = stack.pop()
                if opener != pairs[ch]:
                    problems.append(
                        f"{path.name}:{lineno} {ch} 和 {opened_at} 行的 {opener} 不配对"
                    )
    for opener, lineno in stack:
        problems.append(f"{path.name}:{lineno} {opener} 没有闭合")


def check_ios17(path: Path, code: str):
    for api in IOS17_APIS:
        if re.search(api, code):
            problems.append(f"{path.name} 用了 iOS 17 才有的 API：{api}")


def check_double_sheet(path: Path, code: str):
    count = len(re.findall(r"\.sheet\(", code))
    if count > 1:
        problems.append(f"{path.name} 挂了 {count} 个 .sheet（同一个 View 只认最后一个）")


def check_imports(path: Path, code: str):
    needs = {
        "UIKit": ["UIApplication", "UIActivityViewController", "UIImage", "UIViewController",
                  "UIColor", "UIScreen"],
        "UserNotifications": ["UNUserNotificationCenter", "UNMutableNotificationContent",
                              "UNCalendarNotificationTrigger", "UNNotificationRequest"],
        "Photos": ["PHAsset", "PHPhotoLibrary", "PHImageManager", "PHFetchOptions"],
        "PhotosUI": ["presentLimitedLibraryPicker"],
        "Vision": ["VNRecognizeTextRequest", "VNImageRequestHandler", "VNRecognizedTextObservation",
                   "CGImagePropertyOrientation"],
        "Combine": ["ObservableObject", "@Published"],
        "UniformTypeIdentifiers": ["UTType.json", "allowedContentTypes"],
    }
    for module, symbols in needs.items():
        used = [s for s in symbols if s in code]
        if used and f"import {module}" not in code:
            problems.append(f"{path.name} 用了 {used[0]} 却没 import {module}")


def check_project_yml(path: Path):
    if not path.exists():
        return
    text = path.read_text(encoding="utf-8")
    if "schemes:" not in text:
        problems.append("project.yml 没有 schemes 段，xcodebuild -scheme 会找不到 scheme")


def main():
    files = sorted(SRC.rglob("*.swift"))
    if not files:
        print("没找到 Swift 文件")
        return 1

    for path in files:
        code = path.read_text(encoding="utf-8")
        check_brackets(path, code)
        check_ios17(path, code)
        check_double_sheet(path, code)
        check_imports(path, code)

    check_project_yml(ROOT / "project.yml")

    print(f"检查了 {len(files)} 个 Swift 文件")
    if problems:
        print(f"\n发现 {len(problems)} 个问题：")
        for item in problems:
            print("  -", item)
        return 1
    print("没有发现问题")
    return 0


if __name__ == "__main__":
    sys.exit(main())
