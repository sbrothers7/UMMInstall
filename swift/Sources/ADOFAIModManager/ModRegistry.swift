import Foundation

struct Mod: Identifiable, Hashable {
    let id: String
    let url: String
    let urlV2: String?
    let v3Only: Bool

    init(id: String, url: String, urlV2: String? = nil, v3Only: Bool = false) {
        self.id = id
        self.url = url
        self.urlV2 = urlV2
        self.v3Only = v3Only
    }

    func resolvedURL(isGameV2: Bool) -> String {
        if isGameV2, let v2 = urlV2 { return v2 }
        return url
    }
}

enum ModRegistry {
    static let all: [Mod] = [
        Mod(id: "AdofaiTweaks",           url: "https://github.com/PizzaLovers007/AdofaiTweaks/releases/latest/download/AdofaiTweaks-2.8.1.zip"),
        Mod(id: "TUFHelper",              url: "https://github.com/coyami-ke/TUFHelper/releases/latest/download/TUFHelper.OSX.zip"),
        Mod(id: "JipperResourcePack",     url: "https://github.com/Jongye0l/JipperResourcePack/releases/latest/download/JipperResourcePack.zip"),
        Mod(id: "PACL2",                  url: "https://jalib.jongyeol.kr/downloadMod/PACL2/2.4.205"),
        Mod(id: "TogetherBootstrap",      url: "https://github.com/fangshenghan/TogetherBootstrap-Mod/releases/latest/download/TogetherBootstrap.v1.5.5.zip"),
        Mod(id: "YouTubeStream",          url: "https://bot.adofai.gg/api/mods/YoutubeStream?download=true",
                                          urlV2: "https://fixcdn.hyonsu.com/attachments/886661471533162526/1343622558813130855/YouTubeStream-1.0.3.zip"),
        Mod(id: "KeyboardChatterBlocker", url: "https://github.com/fangshenghan/KeyboardChatterBlocker/releases/download/0.1.0/KeyboardChatterBlocker.v0.1.0.zip",
                                          urlV2: "https://fixcdn.hyonsu.com/attachments/886661471533162526/1239183582975627304/KeyboardChatterBlocker_v0.0.9.zip"),
        Mod(id: "EnhancedEffectRemover",  url: "https://github.com/WsbiMango/EnhancedEffectRemover/releases/download/1.7.0/EnhancedEffectRemover_1.7.0.zip"),
        Mod(id: "XPerfect",               url: "https://github.com/8100print/XPerfect/releases/latest/download/XPerfect.zip"),
        Mod(id: "DesyncFix",              url: "https://fixcdn.hyonsu.com/attachments/886661471533162526/1045847555440910406/DesyncFix-0.0.6.zip"),
        Mod(id: "Bismuth",                url: "https://github.com/sbrothers7/Bismuth/releases/latest/download/Bismuth.zip", v3Only: true),
        Mod(id: "KorenResourcePack",      url: "https://github.com/kkorenn/KorenResourcePack/releases/latest/download/KorenResourcePack.zip", v3Only: true)
    ]
}
