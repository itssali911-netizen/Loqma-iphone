import Foundation
enum MacroKey:String,CaseIterable,Identifiable { case protein,carbs,fat
    var id:String { rawValue };var energy:Double { self == .fat ? 9 : 4 }
    func label(_ l:AppLanguage) -> String { switch self { case .protein:return l.text("البروتين","Protein");case .carbs:return l.text("الكارب","Carbs");case .fat:return l.text("الدهون","Fat") } }
}
extension Nutrition {
    subscript(key:MacroKey) -> Double { get { switch key { case .protein:return protein;case .carbs:return carbs;case .fat:return fat } } set { switch key { case .protein:protein=newValue;case .carbs:carbs=newValue;case .fat:fat=newValue } } }
    func balanced() -> Nutrition { guard kcal.isFinite,kcal>0 else { return .initial };let total=macroCalories;if abs(total-kcal)<0.1{return self};if total<=0{return Nutrition(kcal:kcal,protein:kcal*0.25/4,carbs:kcal*0.45/4,fat:kcal*0.3/9)};return Nutrition(kcal:kcal,protein:protein*kcal/total,carbs:carbs*kcal/total,fat:fat*kcal/total) }
    func editing(_ key:MacroKey,value:Double) -> Nutrition { guard value.isFinite else{return self};var r=balanced();r[key]=min(max(0,value),kcal/key.energy);let other=MacroKey.allCases.filter{$0 != key},rest=max(0,kcal-r[key]*key.energy),energy=other.reduce(0){$0+r[$1]*$1.energy};for k in other { let share=energy>0 ? r[k]*k.energy/energy : (k == .fat ? 0.3 : k == .carbs ? 0.45 : 0.25)/other.reduce(0){$0+($1 == .fat ? 0.3 : $1 == .carbs ? 0.45 : 0.25)};r[k]=rest*share/k.energy };return r }
    func settingCalories(_ calories:Double) -> Nutrition { var r=balanced();let factor=calories/r.kcal;r.kcal=calories;r.protein*=factor;r.carbs*=factor;r.fat*=factor;return r }
    func editingPercent(_ key:MacroKey,value:Double) -> Nutrition { editing(key,value:kcal*min(100,max(0,value))/100/key.energy) }
}
