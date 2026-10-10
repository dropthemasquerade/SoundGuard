import AVFoundation
import Foundation

final class AlertAudioService: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var volume: Float = 1

    func setVolume(_ value: Double) {
        volume = Float(min(1, max(0, value)))
        player?.volume = volume
        player?.isMeteringEnabled = false
    }

    func startLooping() {
        guard player == nil else {
            player?.volume = volume
            if player?.isPlaying == false {
                player?.play()
            }
            return
        }
        guard let url = Bundle.main.url(forResource: "alarm_loop", withExtension: "wav") else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = volume
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            self.player = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if self.player === player, player.numberOfLoops == -1 {
            player.play()
        }
    }
}
