import Charts
import CoreData
import SwiftUI
import Swinject

extension Bolus {
    struct AlternativeBolusCalcRootView: BaseView {
        let resolver: Resolver
        let waitForSuggestion: Bool
        let fetch: Bool
        @StateObject var state: StateModel
        @State private var showInfo = false
        @State private var exceededMaxBolus = false

        private enum Config {
            static let dividerHeight: CGFloat = 2
            static let spacing: CGFloat = 3
            static let overlayColour: Color = .white // Currently not used
        }

        @Environment(\.colorScheme) var colorScheme

        @FetchRequest(
            entity: Meals.entity(),
            sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)]
        ) var meal: FetchedResults<Meals>

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var mealFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        private var gluoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            } else { formatter.maximumFractionDigits = 0 }
            return formatter
        }

        private var fractionDigits: Int {
            if state.units == .mmolL {
                return 1
            } else { return 0 }
        }

        var body: some View {
            Form {
                if state.waitForSuggestion {
                    HStack {
                        Text("Wait please").foregroundColor(.secondary)
                        Spacer()
                        ActivityIndicator(isAnimating: .constant(true), style: .medium) // fix iOS 15 bug
                    }
                }
                Section {
                    if fetch {
                        VStack {
                            if let carbs = meal.first?.carbs, carbs > 0 {
                                HStack {
                                    Text("Carbs")
                                    Spacer()
                                    Text(carbs.formatted())
                                    Text("g")
                                }.foregroundColor(.secondary)
                            }
                            if let fat = meal.first?.fat, fat > 0 {
                                HStack {
                                    Text("Fat")
                                    Spacer()
                                    Text(fat.formatted())
                                    Text("g")
                                }.foregroundColor(.secondary)
                            }
                            if let protein = meal.first?.protein, protein > 0 {
                                HStack {
                                    Text("Protein")
                                    Spacer()
                                    Text(protein.formatted())
                                    Text("g")
                                }.foregroundColor(.secondary)
                            }
                            if let note = meal.first?.note, note != "" {
                                HStack {
                                    Text("Note")
                                    Spacer()
                                    Text(note)
                                }.foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("No Meal")
                    }
                } header: { Text("Meal Summary") }

                Section {
                    Button {
                        let id_ = meal.first?.id ?? ""
                        state.backToCarbsView(complexEntry: fetch, id_)
                    }
                    label: { Text("Edit Meal / Add Meal") }.frame(maxWidth: .infinity, alignment: .center)
                }

                Section {
                    HStack {
                        Button(action: {
                            showInfo.toggle()
                        }, label: {
                            Image(systemName: "info.circle")
                            Text("Calculations")
                        })
                            .foregroundStyle(.blue)
                            .font(.footnote)
                            .buttonStyle(PlainButtonStyle())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if state.fattyMeals {
                            Spacer()
                            Toggle(isOn: $state.useFattyMealCorrectionFactor) {
                                Text("Fatty Meal")
                            }
                            .toggleStyle(CheckboxToggleStyle())
                            .font(.footnote)
                            .onChange(of: state.useFattyMealCorrectionFactor) { _ in
                                state.insulinCalculated = state.calculateInsulin()
                            }
                        }
                    }

                    if state.waitForSuggestion {
                        HStack {
                            Text("Wait please").foregroundColor(.secondary)
                            Spacer()
                            ActivityIndicator(isAnimating: .constant(true), style: .medium) // fix iOS 15 bug
                        }
                    } else {
                        HStack {
                            Text("Recommended Bolus")
                            Spacer()
                            Text(
                                formatter
                                    .string(from: Double(state.insulinCalculated) as NSNumber) ?? ""
                            )
                            Text(
                                NSLocalizedString(" U", comment: "Unit in number of units delivered (keep the space character!)")
                            ).foregroundColor(.secondary)
                        }.contentShape(Rectangle())
                            .onTapGesture { state.amount = state.insulinCalculated }
                    }

                    if !state.waitForSuggestion {
                        HStack {
                            Text("Bolus")
                            Spacer()
                            DecimalTextField(
                                "0",
                                value: $state.amount,
                                formatter: formatter,
                                autofocus: false,
                                cleanInput: true
                            )
                            Text(exceededMaxBolus ? "😵" : " U").foregroundColor(.secondary)
                        }
                        .onChange(of: state.amount) { newValue in
                            if newValue > state.maxBolus {
                                exceededMaxBolus = true
                            } else {
                                exceededMaxBolus = false
                            }
                        }
                    }
                } header: { Text("Bolus Summary") }

                Section {
                    if state.amount == 0, waitForSuggestion {
                        Button { state.showModal(for: nil) }
                        label: { Text("Continue without bolus") }.frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Button { state.add() }
                        label: { Text(exceededMaxBolus ? "Max Bolus exceeded!" : "Enact bolus") }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .foregroundColor(exceededMaxBolus ? .loopRed : .accentColor)
                            .disabled(
                                state.amount <= 0 || state.amount > state.maxBolus
                            )
                    }
                }
            }
            .blur(radius: showInfo ? 3 : 0)
            .navigationTitle("Enact Bolus")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(leading: Button("Close", action: state.hideModal))

            .onAppear {
                configureView {
                    state.waitForSuggestionInitial = waitForSuggestion
                    state.waitForSuggestion = waitForSuggestion
                    state.insulinCalculated = state.calculateInsulin()
                }
            }

            .popup(isPresented: showInfo) {
                bolusInfoAlternativeCalculator
            }
        }

        var changed: Bool {
            ((meal.first?.carbs ?? 0) > 0) || ((meal.first?.fat ?? 0) > 0) || ((meal.first?.protein ?? 0) > 0)
        }

        var hasFatOrProtein: Bool {
            ((meal.first?.fat ?? 0) > 0) || ((meal.first?.protein ?? 0) > 0)
        }

        // Pop-up
        var bolusInfoAlternativeCalculator: some View {
            VStack {
                let unit = NSLocalizedString(" U", comment: "Unit in number of units delivered (keep the space character!)")
                VStack {
                    VStack(spacing: Config.spacing) {
                        HStack {
                            Text("Calculations")
                                .font(.title3).frame(maxWidth: .infinity, alignment: .center)
                        }.padding(10)

                        if fetch {
                            VStack {
                                if let note = meal.first?.note, note != "" {
                                    HStack {
                                        Text("Note")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(note)
                                    }
                                }
                                if let carbs = meal.first?.carbs, carbs > 0 {
                                    HStack {
                                        Text("Carbs")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(mealFormatter.string(from: carbs as NSNumber) ?? "")
                                        Text("g").foregroundColor(.secondary)
                                    }
                                }
                                if let protein = meal.first?.protein, protein > 0 {
                                    HStack {
                                        Text("Protein")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(mealFormatter.string(from: protein as NSNumber) ?? "")
                                        Text("g").foregroundColor(.secondary)
                                    }
                                }
                                if let fat = meal.first?.fat, fat > 0 {
                                    HStack {
                                        Text("Fat")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text(mealFormatter.string(from: fat as NSNumber) ?? "")
                                        Text("g").foregroundColor(.secondary)
                                    }
                                }
                            }.padding()
                        }

                        if fetch { Divider().frame(height: Config.dividerHeight) }

                        VStack {
                            HStack {
                                Text("Carb Ratio")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(state.carbRatio.formatted())
                                Text(NSLocalizedString(" g/U", comment: " grams per Unit"))
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("ISF")
                                    .foregroundColor(.secondary)
                                Spacer()
                                let isf = state.isf
                                Text(isf.formatted())
                                Text(state.units.rawValue + NSLocalizedString("/U", comment: "/Insulin unit"))
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Target Glucose")
                                    .foregroundColor(.secondary)
                                Spacer()
                                let target = state.units == .mmolL ? state.target.asMmolL : state.target
                                Text(
                                    target
                                        .formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits)))
                                )
                                Text(state.units.rawValue)
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Basal")
                                    .foregroundColor(.secondary)
                                Spacer()
                                let basal = state.basal
                                Text(basal.formatted())
                                Text(NSLocalizedString(" U/h", comment: " Units per hour"))
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text("Fraction")
                                    .foregroundColor(.secondary)
                                Spacer()
                                let fraction = state.fraction
                                Text(fraction.formatted())
                            }
                            if state.useFattyMealCorrectionFactor {
                                HStack {
                                    Text("Fatty Meal Factor")
                                        .foregroundColor(.orange)
                                    Spacer()
                                    let fraction = state.fattyMealFactor
                                    Text(fraction.formatted())
                                        .foregroundColor(.orange)
                                }
                            }
                        }.padding()
                    }

                    Divider().frame(height: Config.dividerHeight)

                    VStack(spacing: Config.spacing) {
                        HStack {
                            Text("Glucose")
                                .foregroundColor(.secondary)
                            Spacer()
                            let glucose = state.units == .mmolL ? state.currentBG.asMmolL : state.currentBG
                            Text(glucose.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))))
                            Text(state.units.rawValue)
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: "arrow.right")
                            Spacer()

                            let targetDifferenceInsulin = state.targetDifferenceInsulin
                            // rounding
                            let targetDifferenceInsulinAsDouble = NSDecimalNumber(decimal: targetDifferenceInsulin).doubleValue
                            let roundedTargetDifferenceInsulin = Decimal(round(100 * targetDifferenceInsulinAsDouble) / 100)
                            Text(roundedTargetDifferenceInsulin.formatted())
                            Text(unit)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("IOB")
                                .foregroundColor(.secondary)
                            Spacer()
                            let iob = state.iob
                            // rounding
                            let iobAsDouble = NSDecimalNumber(decimal: iob).doubleValue
                            let roundedIob = Decimal(round(100 * iobAsDouble) / 100)
                            Text(roundedIob.formatted())
                            Text(unit)
                                .foregroundColor(.secondary)
                            Spacer()

                            Image(systemName: "arrow.right")
                            Spacer()

                            let iobCalc = state.iobInsulinReduction
                            // rounding
                            let iobCalcAsDouble = NSDecimalNumber(decimal: iobCalc).doubleValue
                            let roundedIobCalc = Decimal(round(100 * iobCalcAsDouble) / 100)
                            Text(roundedIobCalc.formatted())
                            Text(unit).foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Trend")
                                .foregroundColor(.secondary)
                            Spacer()
                            let trend = state.units == .mmolL ? state.deltaBG.asMmolL : state.deltaBG
                            Text(trend.formatted(.number.grouping(.never).rounded().precision(.fractionLength(fractionDigits))))
                            Text(state.units.rawValue).foregroundColor(.secondary)
                            Spacer()

                            Image(systemName: "arrow.right")
                            Spacer()

                            let trendInsulin = state.fifteenMinInsulin
                            // rounding
                            let trendInsulinAsDouble = NSDecimalNumber(decimal: trendInsulin).doubleValue
                            let roundedTrendInsulin = Decimal(round(100 * trendInsulinAsDouble) / 100)
                            Text(roundedTrendInsulin.formatted())
                            Text(unit)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("COB")
                                .foregroundColor(.secondary)
                            Spacer()
                            let cob = state.cob
                            Text(cob.formatted())

                            let unitGrams = NSLocalizedString(" g", comment: "grams")
                            Text(unitGrams).foregroundColor(.secondary)

                            Spacer()

                            Image(systemName: "arrow.right")
                            Spacer()

                            let insulinCob = state.wholeCobInsulin
                            // rounding
                            let insulinCobAsDouble = NSDecimalNumber(decimal: insulinCob).doubleValue
                            let roundedInsulinCob = Decimal(round(100 * insulinCobAsDouble) / 100)
                            Text(roundedInsulinCob.formatted())
                            Text(unit)
                                .foregroundColor(.secondary)
                        }
                    }.padding()

                    Divider().frame(height: Config.dividerHeight)

                    VStack {
                        HStack {
                            Text("Full Bolus")
                                .foregroundColor(.secondary)
                            Spacer()
                            let insulin = state.roundedWholeCalc
                            Text(insulin.formatted()).foregroundStyle(state.roundedWholeCalc < 0 ? Color.loopRed : Color.primary)
                            Text(unit)
                                .foregroundColor(.secondary)
                        }
                    }.padding(.horizontal)

                    Divider().frame(height: Config.dividerHeight)

                    VStack {
                        HStack {
                            Text("Result")
                                .fontWeight(.bold)
                            Spacer()
                            let fraction = state.fraction
                            Text(fraction.formatted())
                            Text(" x ")
                                .foregroundColor(.secondary)

                            // if fatty meal is chosen
                            if state.useFattyMealCorrectionFactor {
                                let fattyMealFactor = state.fattyMealFactor
                                Text(fattyMealFactor.formatted())
                                    .foregroundColor(.orange)
                                Text(" x ")
                                    .foregroundColor(.secondary)
                            }

                            let insulin = state.roundedWholeCalc
                            Text(insulin.formatted()).foregroundStyle(state.roundedWholeCalc < 0 ? Color.loopRed : Color.primary)
                            Text(unit)
                                .foregroundColor(.secondary)
                            Text(" = ")
                                .foregroundColor(.secondary)

                            let result = state.insulinCalculated
                            // rounding
                            let resultAsDouble = NSDecimalNumber(decimal: result).doubleValue
                            let roundedResult = Decimal(round(100 * resultAsDouble) / 100)
                            Text(roundedResult.formatted())
                                .fontWeight(.bold)
                                .font(.system(size: 16))
                                .foregroundColor(.blue)
                            Text(unit)
                                .foregroundColor(.secondary)
                        }
                    }.padding()

                    Divider().frame(height: Config.dividerHeight)

                    if exceededMaxBolus {
                        HStack {
                            let maxBolus = state.maxBolus
                            let maxBolusFormatted = maxBolus.formatted()
                            Text("Your entered amount was limited by your max Bolus setting of \(maxBolusFormatted)\(unit)!")
                        }
                        .padding()
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.loopRed)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 15)

                // Hide pop-up
                VStack {
                    Button {
                        showInfo = false
                    }
                    label: {
                        Text("OK")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .font(.system(size: 16))
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                }
                .padding(.bottom, 20)
            }
            .font(.footnote)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(colorScheme == .dark ? UIColor.systemGray4 : UIColor.systemGray4).opacity(0.9))
            )
        }
    }
}