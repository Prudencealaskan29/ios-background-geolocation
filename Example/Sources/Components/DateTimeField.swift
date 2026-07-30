// Compact from/to picker field for the Map screen's range bar (Task 5 is the
// actual consumer — this task's file list assigns the file itself).
//
// Swift port of `react-native/example/src/components/DateTimeField.tsx`
// (`flutter/example/lib/src/widgets/date_time_field.dart` is the same port
// for Flutter). Both of those needed extra plumbing SwiftUI doesn't: RN split
// iOS/Android because Android has no combined date+time picker mode; Flutter
// drove two sequential dialogs (`showDatePicker` then `showTimePicker`) for
// the same reason. `DatePicker` with `.compact` style already shows a single
// combined date+time control inline on iOS, so this port needs neither.

import SwiftUI

public struct DateTimeField: View {
    public let label: String
    @Binding public var value: Date?
    public let placeholder: String

    public init(label: String, value: Binding<Date?>, placeholder: String = "set…") {
        self.label = label
        self._value = value
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.secondary)

            if let current = value {
                DatePicker(
                    "",
                    selection: Binding(get: { current }, set: { value = $0 }),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            } else {
                Button(placeholder) { value = Date() }
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }

            if value != nil {
                Button {
                    value = nil
                } label: {
                    Text("✕").foregroundColor(.red)
                }
            }
        }
    }
}
