import Foundation
struct WeightPlan: Codable, Equatable {
    var sex="male";var age:Double=0;var height:Double=0;var weight:Double=0;var targetWeight:Double=0
    var startDay=DayKey.today;var targetDay=DayKey.string(Date().addingTimeInterval(120*86400));var pal:Double=1.6;var activityChange:Double=0;var bodyFat:Double?;var restingCalories:Double?;var carbPercent:Double=50;var sodium:Double=4000;var specialCase=false
    func validate() throws { guard ["male","female"].contains(sex),age.isFinite,(18...100).contains(age),height.isFinite,(120...230).contains(height),weight.isFinite,(35...300).contains(weight),targetWeight.isFinite,(35...300).contains(targetWeight),pal.isFinite,(1.4...2.5).contains(pal),activityChange.isFinite,(-50...100).contains(activityChange),carbPercent.isFinite,(10...80).contains(carbPercent),sodium.isFinite,(500...10000).contains(sodium),DayKey.valid(startDay),DayKey.valid(targetDay),bodyFat.map({$0.isFinite&&(5...60).contains($0)}) ?? true,restingCalories.map({$0.isFinite&&(500...5000).contains($0)}) ?? true else { throw AppError.invalid("راجع بيانات الخطة.","Check your plan inputs.") };if specialCase { throw AppError.invalid("الخطة غير مخصصة للحمل والرضاعة أو لخطة طبية خاصة.","The model does not cover pregnancy, breastfeeding, or a specific medical diet.") } }
}
struct WeightPoint:Identifiable { var day:Int;var kg:Double;var id:Int { day } }
struct WeightResult { var days:Int;var calories:Double;var maintenance:Double;var maintenanceAtGoal:Double;var resting:Double;var points:[WeightPoint];var goals:Nutrition;var lowCalories:Bool }
enum WeightModel {
    // Hall et al. Lancet 2011. Parameters independently implemented from NIDDK BWP.
    struct Baseline { var resting:Double;var maintenance:Double;var fat:Double;var lean:Double;var activity:Double;var constant:Double;var carbs:Double }
    struct State { var fat:Double;var lean:Double;var glycogen:Double;var water:Double;var therm:Double
        func adding(_ a:State,_ f:Double) -> State { State(fat:fat+a.fat*f,lean:lean+a.lean*f,glycogen:glycogen+a.glycogen*f,water:water+a.water*f,therm:therm+a.therm*f) }
        var valid:Bool { [fat,lean,glycogen,water,therm].allSatisfy{$0.isFinite} && fat>0 && lean>0 }
        var mass:Double { fat+lean+3.7*(glycogen-0.5)+water }
    }
    static func days(_ a:String,_ b:String) -> Int { guard let first=DayKey.date(a),let last=DayKey.date(b) else{return 0};return Int((last.timeIntervalSince(first)/86400).rounded()) }
    static func baseline(_ p:WeightPlan) -> Baseline { let bmi=p.weight/pow(p.height/100,2),bf=p.bodyFat ?? min(60,max(0,0.14*p.age+(p.sex=="male" ? 37.31 : 39.96)*log(bmi)-(p.sex=="male" ? 103.94 : 102.01))),resting=p.restingCalories ?? 9.99*p.weight+6.25*p.height-4.92*p.age+(p.sex=="male" ? 5 : -161),maintenance=resting*p.pal,fat=p.weight*bf/100,lean=p.weight-fat,activity=(0.9*maintenance-resting)/p.weight;return Baseline(resting:resting,maintenance:maintenance,fat:fat,lean:lean,activity:activity,constant:0.76*maintenance-22*lean-3.2*fat-activity*p.weight,carbs:p.carbPercent/100*maintenance) }
    static func simulate(_ p:WeightPlan,_ calories:Double,_ days:Int,trajectory:Bool=false) throws -> (state:State,points:[WeightPoint],maintenance:Double) {
        let b=baseline(p),act=b.activity*(1+p.activityChange/100),carbs=calories*p.carbPercent/100,sodium=p.sodium*calories/b.maintenance
        var s=State(fat:b.fat,lean:b.lean,glycogen:0.5,water:0,therm:0.14*b.maintenance),points=[WeightPoint(day:0,kg:p.weight)]
        func derivative(_ v:State) -> State { let share=1.990762711864407/(1.990762711864407+v.fat),flux=carbs-b.carbs/0.25*pow(v.glycogen,2),expend=b.constant+22*v.lean+3.2*v.fat+act*v.mass+v.therm+0.1*calories,allocation=(1-share)*180/9440+share*230/1807,tee=(expend+(calories-flux)*allocation)/(1+allocation),balance=calories-tee-flux;return State(fat:(1-share)*balance/9440,lean:share*balance/1807,glycogen:flux/4180,water:(sodium-p.sodium-3000*v.water-4000*(1-carbs/b.carbs))/3220,therm:(0.14*calories-v.therm)/14) }
        if days>0 { for i in 1...days { let a=derivative(s),c=derivative(s.adding(a,0.5)),d=derivative(s.adding(c,0.5)),e=derivative(s.adding(d,1));s=s.adding(a,1/6).adding(c,2/6).adding(d,2/6).adding(e,1/6);guard s.valid else { throw AppError.invalid("تعذّر حساب هذا المسار.","This trajectory could not be calculated.") };if trajectory&&(i%7==0||i==days){points.append(WeightPoint(day:i,kg:s.mass))} } }
        return (s,points,(b.constant+22*s.lean+3.2*s.fat+act*s.mass)/0.76)
    }
    static func goals(_ p:WeightPlan,_ calories:Double) -> Nutrition { let kcal=calories.rounded(),protein=min(p.weight*1.6,kcal*0.35/4),fat=kcal*0.3/9;return Nutrition(kcal:kcal,protein:protein,carbs:(kcal-protein*4-fat*9)/4,fat:fat).balanced() }
    static func calculate(_ p:WeightPlan) throws -> WeightResult {
        try p.validate();let duration=days(p.startDay,p.targetDay),b=baseline(p);guard (1...730).contains(duration) else { throw AppError.invalid("اختر مدة من يوم إلى سنتين.","Choose a timeline from one day to two years.") };guard !(p.targetWeight<p.weight&&p.targetWeight/pow(p.height/100,2)<18.5) else { throw AppError.invalid("هدف الوزن منخفض لهذه الحاسبة.","The goal is below the supported weight-loss range.") }
        var lo:Double=1000,hi=max(5000,b.maintenance*2);func mass(_ c:Double) -> Double { (try? simulate(p,c,duration).state.mass) ?? -.infinity }
        guard p.targetWeight>=mass(lo),p.targetWeight<=mass(hi) else { throw AppError.invalid("زد المدة أو عدّل وزن الهدف.","Extend the timeline or adjust the goal weight.") }
        for _ in 0..<48 { let c=(lo+hi)/2;if mass(c)<p.targetWeight{lo=c}else{hi=c} };let calories=p.targetWeight==p.weight&&p.activityChange==0 ? b.maintenance : (lo+hi)/2
        guard calories<=10000 else { throw AppError.invalid("النتيجة خارج نطاق أهداف التطبيق.","The result exceeds the app's calorie-goal range.") };let end=try simulate(p,calories,duration,trajectory:true)
        return WeightResult(days:duration,calories:calories,maintenance:b.maintenance,maintenanceAtGoal:end.maintenance,resting:b.resting,points:end.points,goals:goals(p,calories),lowCalories:calories<(p.sex=="male" ? 1500 : 1200))
    }
    static func revised(_ plan:WeightPlan,weight:Double,today:String) throws -> Nutrition { var p=plan;p.weight=weight;p.startDay=today;try p.validate();if days(today,p.targetDay)>0{return try calculate(p).goals};let b=baseline(p);return goals(p,b.maintenance+b.activity*weight*p.activityChange/100/0.76) }
}
