import CosmNotesWork
import SwiftUI

struct WorkProjectEditor: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var name: String
    @State private var color: WorkProjectColor
    @State private var saveError: String?

    let store: WorkStore
    let project: WorkProject?

    init(store: WorkStore, project: WorkProject?) {
        self.store = store
        self.project = project
        _name = State(initialValue: project?.name ?? "")
        _color = State(initialValue: project?.color ?? .blue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(project == nil ? "新增项目" : "编辑项目")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityAddTraits(.isHeader)

            TextField("项目名称", text: $name, prompt: Text("输入项目名称"))
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)

            VStack(alignment: .leading, spacing: 6) {
                Text("配色")
                HStack(spacing: 8) {
                    ForEach(WorkProjectColor.allCases, id: \.self) { option in
                        swatch(option)
                    }
                }
            }

            if let saveError {
                Text(saveError)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .buttonStyle(GlassActionStyle())
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: save)
                    .buttonStyle(GlassActionStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .font(.system(size: 15))
        .padding(18)
        .frame(width: 344)
        .background(.regularMaterial)
        .defaultFocus($nameFocused, true)
    }

    private func swatch(_ option: WorkProjectColor) -> some View {
        Button {
            color = option
        } label: {
            Circle()
                .fill(option.tint)
                .padding(3)
                .overlay {
                    Circle().strokeBorder(color == option ? Color.primary : Color.clear, lineWidth: 1.5)
                }
                .frame(width: 27, height: 27)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityAddTraits(color == option ? .isSelected : [])
        .help(option.label)
    }

    private func save() {
        do {
            if let project {
                try store.updateProject(id: project.id, name: name, color: color)
            } else {
                try store.createProject(name: name, color: color)
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

extension WorkProjectColor {
    var tint: Color {
        switch self {
        case .blue: return .blue
        case .teal: return .teal
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        case .pink: return .pink
        case .purple: return .purple
        case .gray: return .gray
        }
    }

    var label: String {
        switch self {
        case .blue: return "蓝色"
        case .teal: return "青色"
        case .green: return "绿色"
        case .orange: return "橙色"
        case .red: return "红色"
        case .pink: return "粉色"
        case .purple: return "紫色"
        case .gray: return "灰色"
        }
    }
}
