import UIKit
import SwiftUI
import ViewinSDK
import OSLog

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    private let logger = Logger(subsystem: "app.viewin.demo", category: "Application")

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        do {
            #if DEBUG
            try Viewin.start(buildType: .debug)
            #else
            try Viewin.start(buildType: .internalRelease)
            #endif
        } catch {
            logger.error("Failed to start Viewin: \(error.localizedDescription, privacy: .public)")
        }
        return true
    }
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Demo", sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: scene)
        window?.rootViewController = UINavigationController(rootViewController: DemoViewController())
        window?.makeKeyAndVisible()
    }
}

final class DemoTapGestureRecognizer: UITapGestureRecognizer {}

final class DemoViewController: UIViewController, UITableViewDataSource, UIGestureRecognizerDelegate {
    private let titleLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let actionButton = UIButton(type: .system)
    private let cardView = UIView()
    private let cardTap = DemoTapGestureRecognizer()
    private var tapCount = 0
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Viewin Demo"
        view.backgroundColor = .systemBackground
        titleLabel.text = "Inspect a real app"
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        titleLabel.accessibilityIdentifier = "demo.title"
        let subtitle = UILabel()
        subtitle.text = "UIKit · gestures · table rows · SwiftUI host"
        subtitle.font = .preferredFont(forTextStyle: .subheadline)
        subtitle.textColor = .secondaryLabel
        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 18
        cardTap.addTarget(self, action: #selector(tappedCard))
        cardTap.delegate = self
        cardView.addGestureRecognizer(cardTap)
        let avatar = UIImageView(image: UIImage(systemName: "person.crop.circle.fill"))
        avatar.tintColor = .systemBlue
        avatar.contentMode = .scaleAspectFit
        let name = UILabel()
        name.text = "Alex Morgan"
        name.font = .boldSystemFont(ofSize: 22)
        let profile = UIStackView(arrangedSubviews: [avatar, name])
        profile.spacing = 16
        profile.alignment = .center
        avatar.widthAnchor.constraint(equalToConstant: 54).isActive = true
        avatar.heightAnchor.constraint(equalToConstant: 54).isActive = true
        cardView.addSubview(profile)
        profile.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            profile.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            profile.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            profile.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 18),
            profile.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -18)
        ])
        actionButton.configuration = .filled()
        actionButton.setTitle("Edit profile", for: .normal)
        actionButton.accessibilityIdentifier = "demo.edit"
        actionButton.addTarget(self, action: #selector(tappedCard), for: .touchUpInside)
        let host = UIHostingController(rootView: SwiftUIDemoCard())
        addChild(host)
        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitle, cardView, actionButton, host.view])
        stack.axis = .vertical
        stack.spacing = 16
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        host.didMove(toParent: self)
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            actionButton.heightAnchor.constraint(equalToConstant: 44),
            tableView.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    @objc private func tappedCard() {
        tapCount += 1
        titleLabel.text = "Tapped \(tapCount) times"
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 8 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var config = cell.defaultContentConfiguration()
        config.text = "Inspectable row \(indexPath.row)"
        config.secondaryText = "Real UIKit data source index"
        config.image = UIImage(systemName: "square.stack")
        cell.contentConfiguration = config
        return cell
    }
}
