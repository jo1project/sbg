# 產生 assets/fonts/NotoSansTC-Bold-subset.ttf(iOS 上 SystemFont 找不到中文字型,所以字型要打包進專案)。
# 來源:Noto Sans TC 可變字型(OFL,https://github.com/google/fonts/tree/main/ofl/notosanstc)
# 用法:pip install fonttools brotli
#       py godot/tools/make_cjk_font.py <NotoSansTC[wght].ttf>
# 收錄:ASCII、常用標點/全形、Big5 常用字(伺服器傳來的中文 reason 也能顯示)、腳本/場景裡出現的所有字。
import glob, os, sys
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools import subset

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
out = os.path.join(root, "assets", "fonts", "NotoSansTC-Bold-subset.ttf")

chars = set(chr(c) for c in range(0x20, 0x7F))
chars |= set(chr(c) for c in range(0xA0, 0x100))
chars |= set(chr(c) for c in range(0x2000, 0x2070))    # 一般標點(…、—、“” 等)
chars |= set(chr(c) for c in range(0x2190, 0x2200))    # 箭頭
chars |= set(chr(c) for c in range(0x2200, 0x2300))    # 數學符號(≈ 等)
chars |= set(chr(c) for c in range(0x25A0, 0x2700))    # 幾何圖形、雜項符號
chars |= set(chr(c) for c in range(0x3000, 0x3040))    # CJK 標點
chars |= set(chr(c) for c in range(0xFF00, 0xFFF0))    # 全形
# Big5 常用字(0xA440–0xC67E)
for hi in range(0xA4, 0xC7):
    for lo in list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF)):
        try:
            chars.add(bytes([hi, lo]).decode("big5"))
        except UnicodeDecodeError:
            pass
for f in glob.glob(os.path.join(root, "scripts", "**", "*.gd"), recursive=True) + \
         glob.glob(os.path.join(root, "scenes", "**", "*.tscn"), recursive=True):
    chars |= set(open(f, encoding="utf-8").read())
chars = {c for c in chars if c.isprintable() or c == " "}

font = TTFont(sys.argv[1])
font = instantiateVariableFont(font, {"wght": 700})
opts = subset.Options()
opts.layout_features = ["*"]
opts.name_IDs = ["*"]
opts.notdef_outline = True
s = subset.Subsetter(opts)
s.populate(text="".join(chars))
s.subset(font)
font.save(out)
print(out, os.path.getsize(out), "bytes,", len(chars), "chars")
