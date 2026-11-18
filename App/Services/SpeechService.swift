import Foundation
import AVFoundation
import VocabularyKit

/// 发音：优先在线真人发音，无音频时回退系统 TTS
@MainActor
final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVPlayer?

    func pronounce(_ entry: WordEntry) {
        if let audio = entry.phonetics.compactMap(\.audioURL).first {
            // 先查本地缓存，未命中下载后缓存；失败回退在线流播
            Task {
                if let local = await AudioCache.shared.localURL(for: audio) {
                    play(url: local)
                } else {
                    play(url: audio)
                }
            }
        } else {
            speak(entry.word)
        }
    }

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.45
        synthesizer.speak(utterance)
    }

    func play(url: URL) {
        audioPlayer?.pause()
        let player = AVPlayer(url: url)
        audioPlayer = player
        player.play()
    }
}
