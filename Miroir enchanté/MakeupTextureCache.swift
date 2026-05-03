//
//  MakeupTextureCache.swift
//  Miroir enchanté
//

import UIKit

enum MakeupTextureCache {
    enum BlushStyle: Hashable {
        case softRadial
    }

    enum EyeStyle: Hashable {
        case softLid
    }

    struct BlushKey: Hashable {
        var color: ColorKey
        var intensity: Int
        var radius: Int
        var style: BlushStyle
    }

    struct EyeKey: Hashable {
        var color: ColorKey
        var intensity: Int
        var style: EyeStyle
    }

    struct ColorKey: Hashable {
        var red: Int
        var green: Int
        var blue: Int
        var alpha: Int

        init(_ color: UIColor) {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

            self.red = Int((red * 255).rounded())
            self.green = Int((green * 255).rounded())
            self.blue = Int((blue * 255).rounded())
            self.alpha = Int((alpha * 255).rounded())
        }
    }

    private static let lock = NSLock()
    private static var lipNoiseImage: UIImage?
    private static var blushImages: [BlushKey: UIImage] = [:]
    private static var eyeImages: [EyeKey: UIImage] = [:]

    static func lipVerticalNoise() -> UIImage {
        lock.lock()
        if let image = lipNoiseImage {
            lock.unlock()
            return image
        }
        lock.unlock()

        let image = makeVerticalLipNoise()

        lock.lock()
        lipNoiseImage = image
        lock.unlock()

        return image
    }

    static func blushGradient(key: BlushKey) -> UIImage {
        cachedImage(for: key, in: &blushImages) {
            makeRadialGradient(color: key.color.uiColor, alpha: CGFloat(key.intensity) / 100)
        }
    }

    static func eyeGradient(key: EyeKey) -> UIImage {
        cachedImage(for: key, in: &eyeImages) {
            makeEyeGradient(color: key.color.uiColor, alpha: CGFloat(key.intensity) / 100)
        }
    }

    private static func cachedImage<Key: Hashable>(
        for key: Key,
        in storage: inout [Key: UIImage],
        make: () -> UIImage
    ) -> UIImage {
        lock.lock()
        if let image = storage[key] {
            lock.unlock()
            return image
        }
        lock.unlock()

        let image = make()

        lock.lock()
        storage[key] = image
        lock.unlock()

        return image
    }

    private static func makeVerticalLipNoise() -> UIImage {
        let width = 96
        let height = 256
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            let cg = context.cgContext
            var prev: CGFloat = 0.78
            var values: [CGFloat] = []
            values.reserveCapacity(width)

            for _ in 0..<width {
                let target = CGFloat.random(in: 0.55...1.0)
                prev = prev * 0.62 + target * 0.38
                values.append(prev)
            }

            for x in 0..<width {
                cg.setFillColor(UIColor(white: values[x], alpha: 1).cgColor)
                cg.fill(CGRect(x: x, y: 0, width: 1, height: height))
            }

            for _ in 0..<24 {
                let y = Int.random(in: 0..<height)
                let bandHeight = Int.random(in: 1...3)
                let alpha = CGFloat.random(in: 0.05...0.18)
                cg.setFillColor(UIColor(white: 0.5, alpha: alpha).cgColor)
                cg.fill(CGRect(x: 0, y: y, width: width, height: bandHeight))
            }
        }
    }

    private static func makeRadialGradient(color: UIColor, alpha: CGFloat) -> UIImage {
        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let colors = [
                color.withAlphaComponent(alpha).cgColor,
                color.withAlphaComponent(alpha * 0.45).cgColor,
                UIColor.clear.cgColor
            ] as CFArray
            let locations: [CGFloat] = [0, 0.56, 1]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) else { return }
            cg.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                startRadius: 0,
                endCenter: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                endRadius: size.width * 0.5,
                options: []
            )
        }
    }

    private static func makeEyeGradient(color: UIColor, alpha: CGFloat) -> UIImage {
        let size = CGSize(width: 160, height: 96)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            let colors = [
                color.withAlphaComponent(alpha).cgColor,
                color.withAlphaComponent(alpha * 0.35).cgColor,
                UIColor.clear.cgColor
            ] as CFArray
            let locations: [CGFloat] = [0, 0.62, 1]
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors,
                locations: locations
            ) else { return }
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: size.width * 0.5, y: 0),
                end: CGPoint(x: size.width * 0.5, y: size.height),
                options: []
            )
        }
    }
}

private extension MakeupTextureCache.ColorKey {
    var uiColor: UIColor {
        UIColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha) / 255
        )
    }
}
