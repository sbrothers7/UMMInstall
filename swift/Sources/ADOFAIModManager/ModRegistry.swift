import Foundation

struct Mod: Identifiable, Hashable {
    let id: String
    let url: String
}

enum ModRegistry {
    static let all: [Mod] = [
        Mod(id: "AdofaiTweaks",           url: "https://github.com/PizzaLovers007/AdofaiTweaks/releases/latest/download/AdofaiTweaks-2.8.1.zip"),
        Mod(id: "TUFHelper",              url: "https://github.com/coyami-ke/TUFHelper/releases/latest/download/TUFHelper.OSX.zip"),
        Mod(id: "JipperResourcePack",     url: "https://github.com/Jongye0l/JipperResourcePack/releases/latest/download/JipperResourcePack.zip"),
        Mod(id: "PACL2",                  url: "https://jalib.jongyeol.kr/downloadMod/PACL2/2.4.205"),
        Mod(id: "TogetherBootstrap",      url: "https://github.com/fangshenghan/TogetherBootstrap-Mod/releases/latest/download/TogetherBootstrap.v1.5.5.zip"),
        Mod(id: "YouTubeStream",          url: "https://bot.adofai.gg/api/mods/YoutubeStream?download=true"),
        Mod(id: "KeyboardChatterBlocker", url: "https://github.com/fangshenghan/KeyboardChatterBlocker/releases/download/0.1.0/KeyboardChatterBlocker.v0.1.0.zip"),
        Mod(id: "EnhancedEffectRemover",  url: "https://github.com/WsbiMango/EnhancedEffectRemover/releases/download/1.7.0/EnhancedEffectRemover_1.7.0.zip"),
        Mod(id: "XPerfect",               url: "https://github.com/8100print/XPerfect/releases/latest/download/XPerfect.zip"),
        Mod(id: "DesyncFix",              url: "https://fixcdn.hyonsu.com/attachments/886661471533162526/1045847555440910406/DesyncFix-0.0.6.zip")
    ]
}
