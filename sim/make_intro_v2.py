from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn

OUT = r"D:\AAA_University\Anlu\Project\doc\浣滃搧绠€浠?docx"

TITLE = "搴楀唴闊充箰鐢靛瓙鑿滃崟"
SUBTITLE = "鈥斺€斿熀浜庡畨璺?EG4S20 鐨?FPGA 瀹炵幇"

PARAS = [
    "杩欐槸涓€鍙版斁鍦ㄥ挅鍟￠閲岀殑鐢靛瓙鑿滃崟銆傚睆骞曚笂鍥涢〉鑿滃崟杞祦缈诲姩锛屾瘡椤典袱娆惧晢鍝侊紝鐓х墖銆佸悕绉般€佷粙缁嶅拰浠锋牸閮藉湪璇ュ湪鐨勪綅缃笂锛?
    "鑳屾櫙鏀剧潃涓€棣栭挗鐞存洸锛屽睆骞曚笅鏂圭殑棰戣氨璺熺潃闊充箰璧蜂紡銆傛暣鍙拌澶囧彧鏈変竴鍧?FPGA锛屾病鏈夊鐞嗗櫒銆佹病鏈夋搷浣滅郴缁燂紝"
    "浠庤鍗°€佽В鐮併€佺缉鏀俱€佸彔鍔犲埌杈撳嚭 HDMI锛屽叏閮ㄧ敱纭欢閫昏緫瀹屾垚銆?,

    "涓婄數鍚庢澘瀛愭壂鎻?TF 鍗★紝鎶婂洓寮犺彍鍗曞浘鎸夋瘮渚嬬缉鍒?640脳480 鍐欒繘 SDRAM 鐨勫洓涓尯甯搁┗锛岀炕椤靛洜姝ゆ病鏈夊姞杞界瓑寰呫€?
    "鍟嗗搧鐨勪腑鏂囨枃瀛椾笉鐢诲湪鍥鹃噷锛岃€屾槸鍗曠嫭鍋氭垚浣嶅浘鎺╄啘瀛樻斁鍦ㄥ崱涓婏紝鐢?FPGA 鍦ㄦ樉绀洪€氳矾涓婂彔鍔犫€斺€?
    "鏂囧瓧鍥犳鍙互浠庝袱渚ч€愬儚绱犳粦鍏ワ紝鎹㈡枃妗堟椂涔熷彧鏀规帺鑶溿€佷笉鍔ㄥ簳鍥俱€傞暱鎸夋寜閿彲浠ユ妸褰撳墠杩欏紶鍗＄墖鏀惧ぇ涓ゅ€嶏紝"
    "鏀惧ぇ鏃舵寜鐩搁偦鍍忕礌鍔犳潈杩囨浮锛岀敾闈笉浼氬嚭鐜扮‖鍧楃殑閿娇锛涙斁澶ф椂鍗￠潰涓婄殑鏂囧瓧鑷姩闅愬幓锛岃鐓х墖鍗犳弧鏁村睆銆?,

    "澹伴煶鐢?FPGA 鐩存帴浜х敓锛氳鍗′笂鐨勮８ PCM 娴侊紝缁忛煶閲忔帶鍒跺悗閫佽繘 HDMI锛涘崱涓婃病鏈夋洸鐩椂鍒囨崲鍒板唴缃祴璇曢煶锛?
    "骞舵妸闊抽珮鍒绘剰瀵归綈鍒伴璋卞垎鏋愮殑棰戠偣锛屾煴褰㈠洜姝ょǔ瀹氥€佷笉鏉ュ洖鎶栧姩銆傚垏姝屻€佸揩杩涘崄绉掋€佽皟鑺備寒搴︿笌瀵规瘮搴﹂兘鍦ㄦ寜閿拰闈㈡澘涓婂畬鎴愶紝"
    "鍙充笂瑙掓樉绀烘洸鐩笌鍓╀綑鏃堕棿锛屽乏涓婅鏄剧ず褰撳墠椤电爜銆?,

    "鏁村潡鏉垮瓙鐨勯€昏緫璧勬簮鐢ㄤ簡 96%锛岃棰戞椂閽熷皻鏈?13 绾崇浣欓噺锛岀患鍚堟棤榛戠洅锛屽浐浠跺凡鐑у叆 Flash锛屼笂鐢靛嵆鍙繍琛屻€?,
]


def set_font(run, name="寰蒋闆呴粦", size=11, bold=False):
    run.font.name = name
    run.font.size = Pt(size)
    run.font.bold = bold
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.find(qn('w:rFonts'))
    if rfonts is None:
        rfonts = rpr.makeelement(qn('w:rFonts'), {})
        rpr.append(rfonts)
    rfonts.set(qn('w:eastAsia'), name)


doc = Document()
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
set_font(p.add_run(TITLE), size=18, bold=True)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
set_font(p.add_run(SUBTITLE), size=11)

for body in PARAS:
    q = doc.add_paragraph()
    q.paragraph_format.space_after = Pt(8)
    q.paragraph_format.first_line_indent = Pt(22)
    set_font(q.add_run(body), size=11)

doc.save(OUT)
print("saved:", OUT)
print("姝ｆ枃瀛楃鏁?", sum(len(x) for x in PARAS), " 鏍囬+鍓爣棰?", len(TITLE) + len(SUBTITLE))

