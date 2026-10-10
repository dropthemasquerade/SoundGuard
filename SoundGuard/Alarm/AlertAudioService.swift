import AVFoundation
import Foundation

final class AlertAudioService: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var volume: Float = 1
    private var loadedTone: AlarmTone?

    func setVolume(_ value: Double) {
        volume = Float(min(1, max(0, value)))
        player?.volume = volume
        player?.isMeteringEnabled = false
    }

    func startLooping(tone: AlarmTone) {
        if player != nil, loadedTone == tone {
            player?.volume = volume
            if player?.isPlaying == false {
                player?.play()
            }
            return
        }
        player?.stop()
        player = nil
        loadedTone = nil
        guard let url = tone.fileURL() else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = volume
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
            self.loadedTone = tone
        } catch {
            self.player = nil
            self.loadedTone = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        loadedTone = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if self.player === player, player.numberOfLoops == -1 {
            player.play()
        }
    }
}
