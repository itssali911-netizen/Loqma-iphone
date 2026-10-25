import React, { useState, useMemo, useEffect } from 'react';
import {
  Search,
  ChevronLeft,
  ChevronRight,
  ChevronDown,
  Dumbbell,
  Utensils,
  MessageSquare,
  Sparkles,
  SlidersHorizontal,
  FileText,
  Play,
  Activity,
  Flame,
  Eye,
  Columns,
  Layers,
  Globe,
  RotateCcw,
  Check
} from 'lucide-react';

// Exact Reference Search Results Dataset (matching every card, icon, badge color, and % match)
const REFERENCE_RESULTS = [
  {
    id: 'res-1',
    titleEn: 'Virtual AI Coach',
    titleAr: 'المدرب الذكي الافتراضي (لقمة)',
    luqmaTitleEn: 'AI Luqma Smart Chef',
    badgeEn: 'Fitness',
    badgeLuqmaEn: 'Healthy',
    badgeAr: 'صحي',
    badgeBg: '#4E7D2B', // Exact olive-green pill
    matchPct: 98,
    iconType: 'sparkle',
    category: 'workouts'
  },
  {
    id: 'res-2',
    titleEn: 'Activity Tracker',
    titleAr: 'متتبع السعرات والنشاط',
    luqmaTitleEn: 'Calorie & Macro Tracker',
    badgeEn: 'Workout',
    badgeLuqmaEn: 'Nutrition',
    badgeAr: 'تغذية',
    badgeBg: '#1D4ED8', // Exact royal-blue pill
    matchPct: 88,
    iconType: 'runner',
    category: 'workouts'
  },
  {
    id: 'res-3',
    titleEn: 'Coach Farnese Vandimion',
    titleAr: 'الشيف وأخصائي التغذية فارنيز',
    luqmaTitleEn: 'Chef Farnese Vandimion',
    badgeEn: 'Coaching',
    badgeLuqmaEn: 'High Protein',
    badgeAr: 'إرشاد غذائي',
    badgeBg: '#84262E', // Exact crimson-burgundy pill
    matchPct: 78,
    iconType: 'dumbbell',
    category: 'community'
  },
  {
    id: 'res-4',
    titleEn: 'AI Fitness Assistant',
    titleAr: 'مساعد لقمة الذكي للتغذية',
    luqmaTitleEn: 'AI Luqma Nutrition Assistant',
    badgeEn: 'Fitness',
    badgeLuqmaEn: 'Meals',
    badgeAr: 'وجبات',
    badgeBg: '#4B5262', // Exact slate-grey pill
    matchPct: 55,
    iconType: 'document',
    category: 'meals'
  },
  {
    id: 'res-5',
    titleEn: 'Workout Course Suggesti...',
    titleAr: 'جدول الوجبات الأسبوعي المقترح...',
    luqmaTitleEn: 'Weekly Meal Plan Suggesti...',
    badgeEn: 'Workout Schedule',
    badgeLuqmaEn: 'Meal Schedule',
    badgeAr: 'جدول الوجبات',
    badgeBg: '#6B21A8', // Exact purple pill
    matchPct: 48,
    iconType: 'play',
    category: 'meals'
  },
  {
    id: 'res-6',
    titleEn: 'AI Workout Assessment',
    titleAr: 'التقييم الغذائي الذكي (لقمة)',
    luqmaTitleEn: 'AI Luqma Diet Assessment',
    badgeEn: 'Fitness',
    badgeLuqmaEn: 'Healthy',
    badgeAr: 'صحي',
    badgeBg: '#4E7D2B', // Exact olive-green pill
    matchPct: 35,
    iconType: 'sparkle',
    category: 'workouts'
  }
];

const HEADER_PILLS = [
  { id: 'workouts', labelEn: 'Workouts', labelLuqmaEn: 'Workouts', labelAr: 'التمارين', icon: 'dumbbell' },
  { id: 'meals', labelEn: 'Meals', labelLuqmaEn: 'Meals', labelAr: 'الوجبات', icon: 'meals' },
  { id: 'community', labelEn: 'Community', labelLuqmaEn: 'Community', labelAr: 'المجتمع', icon: 'community' },
  { id: 'ai', labelEn: '', labelLuqmaEn: '', labelAr: '', icon: 'sparkle' }
];

export default function App() {
  // Studio Controls
  const [viewMode, setViewMode] = useState('all-three'); // 'all-three' | 'interactive' | 'specs'
  const [activeScreenState, setActiveScreenState] = useState('results'); // 'results' | 'not-found' | 'loading'
  const [contentPreset, setContentPreset] = useState('exact'); // 'exact' (100% verbatim text from screenshot) | 'luqma-en' | 'luqma-ar'
  const [searchQuery, setSearchQuery] = useState('Fitness AI Assista');
  const [selectedPill, setSelectedPill] = useState(null);
  const [sortAsc, setSortAsc] = useState(false);
  const [activeDot, setActiveDot] = useState(0);
  const [selectedResultItem, setSelectedResultItem] = useState(null);

  const isRtl = contentPreset === 'luqma-ar';

  // Animate the 8-dot spinner gently when in interactive loading mode
  useEffect(() => {
    const timer = setInterval(() => {
      setActiveDot((prev) => (prev + 1) % 8);
    }, 180);
    return () => clearInterval(timer);
  }, []);

  const displayedResults = useMemo(() => {
    const list = [...REFERENCE_RESULTS];
    if (sortAsc) {
      list.sort((a, b) => a.matchPct - b.matchPct);
    } else {
      list.sort((a, b) => b.matchPct - a.matchPct);
    }
    return list;
  }, [sortAsc]);

  // Custom exact SVG icons matching the uploaded screenshot 100%
  const renderCardIcon = (type) => {
    switch (type) {
      case 'sparkle':
        return (
          <svg viewBox="0 0 24 24" className="w-[22px] h-[22px] text-[#D4D7DD]" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 3 L14.6 9.4 L21 12 L14.6 14.6 L12 21 L9.4 14.6 L3 12 L9.4 9.4 Z" />
          </svg>
        );
      case 'runner':
        return (
          <svg viewBox="0 0 24 24" className="w-[22px] h-[22px] text-[#D4D7DD]" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="13.5" cy="5.5" r="2" />
            <path d="M7 11.5 L11 9.5 L14.5 11.5 L17.5 9.5" />
            <path d="M12.5 11 L10.5 15.5 L7.5 19.5" />
            <path d="M11.5 14.5 L14.5 16.5 L14.5 20.5" />
          </svg>
        );
      case 'dumbbell':
        return (
          <svg viewBox="0 0 24 24" className="w-[22px] h-[22px] text-[#D4D7DD]" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M6.5 6.5 L17.5 17.5" />
            <path d="M4 9 L9 4" />
            <path d="M2.5 6.5 L6.5 2.5" />
            <path d="M15 20 L20 15" />
            <path d="M17.5 21.5 L21.5 17.5" />
          </svg>
        );
      case 'document':
        return (
          <svg viewBox="0 0 24 24" className="w-[22px] h-[22px] text-[#D4D7DD]" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8z" />
            <polyline points="14 3 14 8 19 8" />
            <line x1="9" y1="13" x2="15" y2="13" />
            <line x1="9" y1="17" x2="13" y2="17" />
          </svg>
        );
      case 'play':
        return (
          <svg viewBox="0 0 24 24" className="w-[22px] h-[22px] text-[#D4D7DD]" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <polygon points="8 5 19 12 8 19 8 5" />
          </svg>
        );
      default:
        return <Sparkles className="w-5 h-5 text-[#D4D7DD]" />;
    }
  };

  const renderPillIcon = (type) => {
    switch (type) {
      case 'dumbbell':
        return (
          <svg viewBox="0 0 24 24" className="w-3.5 h-3.5 text-white" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
            <path d="M6 6 L18 18" />
            <path d="M3.5 8.5 L8.5 3.5" />
            <path d="M15.5 20.5 L20.5 15.5" />
          </svg>
        );
      case 'meals':
        return <Utensils className="w-3.5 h-3.5 text-white" />;
      case 'community':
        return <MessageSquare className="w-3.5 h-3.5 text-white" />;
      case 'sparkle':
        return (
          <svg viewBox="0 0 24 24" className="w-3.5 h-3.5 text-white" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M12 3 L14.5 9.5 L21 12 L14.5 14.5 L12 21 L9.5 14.5 L3 12 L9.5 9.5 Z" />
          </svg>
        );
      default:
        return null;
    }
  };

  // Exact 3D Tilted Gold Magnifying Glass Illustration for "Woops, Not Found"
  const renderMagnifyingGlassIllustration = () => (
    <div className="relative w-[220px] h-[160px] flex items-center justify-center mx-auto mb-5 select-none">
      <svg viewBox="0 0 240 175" className="w-full h-full overflow-visible">
        <defs>
          <linearGradient id="goldRimOuter" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#DFAD62" />
            <stop offset="55%" stopColor="#B8833B" />
            <stop offset="100%" stopColor="#84571F" />
          </linearGradient>
          <linearGradient id="goldRimTop" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" stopColor="#E4B56B" />
            <stop offset="100%" stopColor="#C18D42" />
          </linearGradient>
          <linearGradient id="glassLens" x1="0%" y1="0%" x2="0%" y2="100%">
            <stop offset="0%" stopColor="#1B303E" />
            <stop offset="100%" stopColor="#264050" />
          </linearGradient>
          <linearGradient id="handleGrad" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#DDA95E" />
            <stop offset="60%" stopColor="#B58038" />
            <stop offset="100%" stopColor="#7C501B" />
          </linearGradient>
        </defs>

        {/* Subtle Dark Floor Shadow Ellipse */}
        <ellipse cx="132" cy="128" rx="68" ry="12" fill="#050608" opacity="0.85" />

        {/* Tilted Handle on Bottom-Left */}
        <g transform="translate(88, 102) rotate(-32)">
          {/* Handle 3D Depth Base */}
          <rect x="-58" y="-8" width="64" height="20" rx="10" fill="#7D521D" />
          {/* Handle Top Surface */}
          <rect x="-58" y="-12" width="64" height="18" rx="9" fill="url(#handleGrad)" />
          {/* Handle Highlight Strip */}
          <rect x="-52" y="-8" width="46" height="4" rx="2" fill="#EAC180" opacity="0.45" />
        </g>

        {/* 3D Magnifying Glass Head (Tilted Perspective Ellipse) */}
        <g transform="translate(132, 74) rotate(-6)">
          {/* Outer 3D Extrusion Base */}
          <ellipse cx="0" cy="7" rx="58" ry="42" fill="#7C511C" />
          {/* Main Gold Rim */}
          <ellipse cx="0" cy="0" rx="58" ry="42" fill="url(#goldRimTop)" />
          {/* Inner Dark Ring */}
          <ellipse cx="0" cy="0" rx="50" ry="35" fill="#1A1B1E" />
          {/* Inner Bronze Bevel */}
          <ellipse cx="0" cy="2" rx="46" ry="31.5" fill="#7E5522" />
          {/* Dark Blue-Slate Glass Lens */}
          <ellipse cx="0" cy="1" rx="43" ry="29" fill="url(#glassLens)" />
          {/* Curved Top Light Reflection Arc */}
          <path
            d="M -27 -6 Q 0 -23 28 -5"
            fill="none"
            stroke="#98B5C4"
            strokeWidth="8.5"
            strokeLinecap="round"
            opacity="0.85"
          />
          {/* Subtle Bottom Rim Glint */}
          <path
            d="M -22 20 Q 2 27 24 18"
            fill="none"
            stroke="#6C8FA1"
            strokeWidth="2.5"
            strokeLinecap="round"
            opacity="0.65"
          />
        </g>
      </svg>
    </div>
  );

  // Reusable Full Mobile Screen Renderer for each state ('results' | 'not-found' | 'loading')
  const renderSearchScreen = (screenMode, isStaticRing = false) => {
    // Dynamic header orange tone matching each screenshot (#F5720A for Results/NotFound, #E67824 for Loading)
    const headerBg = screenMode === 'loading' ? '#E67824' : '#F6720A';

    return (
      <div
        dir={isRtl ? 'rtl' : 'ltr'}
        className="relative w-[360px] h-[780px] rounded-[42px] bg-[#0D0E11] text-white overflow-hidden shadow-[0_20px_50px_rgba(0,0,0,0.75)] flex flex-col justify-between select-none flex-shrink-0 border border-white/10"
      >
        {/* 1. TOP ORANGE HEADER CONTAINER */}
        <div
          style={{ backgroundColor: headerBg }}
          className="px-5 pt-3.5 pb-5 space-y-4 flex-shrink-0"
        >
          {/* iOS Status Bar (9:41 + Signal/Wifi/Battery) */}
          <div className="flex items-center justify-between text-[13px] font-bold tracking-tight text-white px-1">
            <span>9:41</span>
            <div className="flex items-center gap-1.5">
              {/* Signal Bars */}
              <div className="flex items-end gap-[2px] h-3">
                <span className="w-[2.5px] h-1.5 bg-white rounded-full" />
                <span className="w-[2.5px] h-2 bg-white rounded-full" />
                <span className="w-[2.5px] h-2.5 bg-white rounded-full" />
                <span className="w-[2.5px] h-3 bg-white rounded-full" />
              </div>
              {/* Wifi Icon */}
              <svg viewBox="0 0 24 24" className="w-4 h-3.5 text-white" fill="currentColor">
                <path d="M12 18c1.1 0 2 .9 2 2s-.9 2-2 2-2-.9-2-2 .9-2 2-2zm-4.9-2.3l1.4 1.4C9.4 16.4 10.6 16 12 16s2.6.4 3.5 1.1l1.4-1.4C15.6 14.6 13.9 14 12 14s-3.6.6-4.9 1.7zm-2.8-2.8l1.4 1.4C7.3 13 9.5 12 12 12s4.7 1 6.3 2.3l1.4-1.4C17.7 11.1 15 10 12 10s-5.7 1.1-7.7 2.9z" />
              </svg>
              {/* Battery Icon */}
              <div className="flex items-center">
                <div className="w-[22px] h-[11px] rounded-[3px] border border-white/90 p-[1.5px] flex items-center">
                  <div className="w-full h-full bg-white rounded-[1px]" />
                </div>
                <div className="w-[1.5px] h-1 bg-white/90 rounded-r-full ml-[1px]" />
              </div>
            </div>
          </div>

          {/* Back Squircle Button + "Search" Title */}
          <div className="flex items-center gap-3.5 pt-0.5">
            <button
              onClick={() => setActiveScreenState('results')}
              className="w-[42px] h-[42px] rounded-[13px] bg-white/20 flex items-center justify-center active:scale-95 transition-transform"
              title="Back"
            >
              {isRtl ? (
                <ChevronRight className="w-5 h-5 text-white stroke-[2.2]" />
              ) : (
                <ChevronLeft className="w-5 h-5 text-white stroke-[2.2]" />
              )}
            </button>
            <h1 className="text-[20px] font-extrabold tracking-tight text-white">
              {isRtl ? 'البحث' : 'Search'}
            </h1>
          </div>

          {/* Dark Search Input Box (#101114) */}
          <div className="bg-[#101114] rounded-[18px] h-[52px] px-4 flex items-center justify-between shadow-inner">
            <input
              type="text"
              value={
                isRtl && searchQuery === 'Fitness AI Assista'
                  ? 'مساعد لقمة الذكي'
                  : searchQuery
              }
              onChange={(e) => {
                const val = e.target.value;
                setSearchQuery(val);
              }}
              placeholder={isRtl ? 'ابحث في لقمة...' : 'Fitness AI Assista'}
              className="bg-transparent text-[14.5px] font-medium text-[#E4E6EB] placeholder-[#9EA2AE] w-full focus:outline-none"
            />
            <button
              onClick={() =>
                setActiveScreenState(
                  activeScreenState === 'results' ? 'loading' : 'results'
                )
              }
              className="text-white hover:opacity-80 flex-shrink-0"
              title="Search"
            >
              <Search className="w-[19px] h-[19px] text-white stroke-[2.2]" />
            </button>
          </div>

          {/* Horizontal Outlined Filter Pills Row */}
          <div className="flex items-center gap-2 overflow-x-auto no-scrollbar pt-0.5 -mx-1 px-1">
            {HEADER_PILLS.map((pill) => {
              const isSelected = selectedPill === pill.id;
              const pillText =
                contentPreset === 'luqma-ar'
                  ? pill.labelAr
                  : contentPreset === 'luqma-en'
                  ? pill.labelLuqmaEn
                  : pill.labelEn;

              return (
                <button
                  key={pill.id}
                  onClick={() =>
                    setSelectedPill(selectedPill === pill.id ? null : pill.id)
                  }
                  className={`h-[34px] px-3 rounded-[10px] border flex items-center gap-1.5 text-[12px] font-semibold whitespace-nowrap transition-all flex-shrink-0 ${
                    isSelected
                      ? 'bg-white text-[#F6720A] border-white shadow-sm'
                      : 'bg-white/10 border-white/75 text-white hover:bg-white/20'
                  }`}
                >
                  <span className={isSelected ? 'brightness-0' : ''}>
                    {renderPillIcon(pill.icon)}
                  </span>
                  {pillText && <span>{pillText}</span>}
                </button>
              );
            })}
          </div>
        </div>

        {/* 2. DARK BODY SECTION (#0D0E11) */}
        <div className="flex-1 bg-[#0D0E11] px-4 pt-4 pb-6 flex flex-col justify-between overflow-y-auto no-scrollbar">
          {/* STATE A: SEARCH RESULTS */}
          {screenMode === 'results' && (
            <div className="space-y-3.5">
              {/* Results Count & Match% Filter Row */}
              <div className="flex items-center justify-between px-0.5">
                <span className="text-[14.5px] font-extrabold text-white tracking-tight">
                  {isRtl ? 'تم العثور على 8 نتائج.' : '8 results found.'}
                </span>

                <button
                  onClick={() => setSortAsc(!sortAsc)}
                  className="h-[30px] px-2.5 rounded-[8px] border border-[#3E424B] bg-[#14161B] flex items-center gap-1.5 text-[11.5px] font-semibold text-[#C8CBD2] hover:border-white/40 transition-colors"
                >
                  <SlidersHorizontal className="w-3.5 h-3.5 text-[#D0D3DA]" />
                  <span>{isRtl ? 'نسبة التطابق%' : 'Match%'}</span>
                  <ChevronDown className="w-3 h-3 text-[#A0A5B1]" />
                </button>
              </div>

              {/* Vertical List of 6 Result Cards */}
              <div className="space-y-2.5">
                {displayedResults.map((item) => {
                  const title =
                    contentPreset === 'luqma-ar'
                      ? item.titleAr
                      : contentPreset === 'luqma-en'
                      ? item.luqmaTitleEn
                      : item.titleEn;

                  const badgeText =
                    contentPreset === 'luqma-ar'
                      ? item.badgeAr
                      : contentPreset === 'luqma-en'
                      ? item.badgeLuqmaEn
                      : item.badgeEn;

                  return (
                    <div
                      key={item.id}
                      onClick={() => setSelectedResultItem(item)}
                      role="button"
                      tabIndex={0}
                      className="bg-[#1D2026] hover:bg-[#242830] rounded-[22px] p-3 flex items-center justify-between gap-3 cursor-pointer transition-all active:scale-[0.99]"
                    >
                      <div className="flex items-center gap-3.5 min-w-0">
                        {/* Left 52x52 Dark Grey Icon Squircle (#32363E) */}
                        <div className="w-[52px] h-[52px] rounded-[16px] bg-[#32363E] flex items-center justify-center flex-shrink-0">
                          {renderCardIcon(item.iconType)}
                        </div>

                        {/* Title + Colored Category Badge + Match% */}
                        <div className="space-y-1.5 min-w-0">
                          <h3 className="text-[14.5px] font-extrabold text-white tracking-tight truncate">
                            {title}
                          </h3>
                          <div className="flex items-center gap-2">
                            <span
                              style={{ backgroundColor: item.badgeBg }}
                              className="px-2.5 py-[3px] rounded-[6px] text-[11px] font-semibold text-white leading-tight"
                            >
                              {badgeText}
                            </span>
                            <span className="text-[12px] font-medium text-[#9EA3AE]">
                              {isRtl
                                ? `${item.matchPct}% تطابق`
                                : `${item.matchPct}% Match`}
                            </span>
                          </div>
                        </div>
                      </div>

                      {/* Right Chevron */}
                      <div className="pr-1 text-[#9EA3AE] flex-shrink-0">
                        {isRtl ? (
                          <ChevronLeft className="w-4 h-4 stroke-[2.2]" />
                        ) : (
                          <ChevronRight className="w-4 h-4 stroke-[2.2]" />
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* STATE B: WOOPS, NOT FOUND */}
          {screenMode === 'not-found' && (
            <div className="flex-1 flex flex-col items-center justify-center text-center px-3 -mt-6">
              {renderMagnifyingGlassIllustration()}

              <h2 className="text-[21px] font-extrabold text-white tracking-tight flex items-center justify-center gap-2 mb-2.5">
                <span>
                  {isRtl ? 'عذراً، لم يتم العثور على نتائج' : 'Woops, Not Found'}
                </span>
                <span className="text-[21px] leading-none">😢</span>
              </h2>

              <p className="text-[13.5px] font-normal text-[#969AA3] leading-[1.55] max-w-[285px]">
                {isRtl
                  ? 'للأسف، الكلمة المفتاحية التي أدخلتها غير موجودة. يرجى تجربة كلمة أخرى أو التحقق مرة ثانية.'
                  : 'Unfortunately, the key you entered cannot be found. Please try another keyword or check again.'}
              </p>
            </div>
          )}

          {/* STATE C: LOADING... */}
          {screenMode === 'loading' && (
            <div className="flex-1 flex flex-col items-center justify-center text-center -mt-4">
              {/* 8-Dot Circular Ring Spinner (Top dot #F07B24, other 7 dots #35383F) */}
              <div className="relative w-[96px] h-[96px] mb-6">
                {[0, 1, 2, 3, 4, 5, 6, 7].map((idx) => {
                  const angleDeg = idx * 45 - 90; // 0 is top (-90 deg)
                  const angleRad = (angleDeg * Math.PI) / 180;
                  const radius = 34;
                  const cx = 48 + radius * Math.cos(angleRad);
                  const cy = 48 + radius * Math.sin(angleRad);
                  const isOrange = isStaticRing ? idx === 0 : idx === activeDot;

                  return (
                    <span
                      key={idx}
                      style={{
                        left: `${cx - 9.5}px`,
                        top: `${cy - 9.5}px`,
                        backgroundColor: isOrange ? '#F07B24' : '#35383F'
                      }}
                      className="absolute w-[19px] h-[19px] rounded-full transition-colors duration-150"
                    />
                  );
                })}
              </div>

              <span className="text-[17px] font-extrabold text-white tracking-tight">
                {isRtl ? 'جاري التحميل...' : 'Loading...'}
              </span>
            </div>
          )}

          {/* Bottom iOS Home Indicator Bar */}
          <div className="pt-4 flex justify-center flex-shrink-0">
            <div className="w-[128px] h-[4.5px] rounded-full bg-white" />
          </div>
        </div>

        {/* Interactive Item Details Toast/Sheet */}
        {selectedResultItem && (
          <div className="absolute inset-0 bg-black/75 z-30 flex items-end">
            <div className="w-full bg-[#1D2026] border-t border-[#32363E] rounded-t-3xl p-5 space-y-3">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-11 h-11 rounded-xl bg-[#32363E] flex items-center justify-center">
                    {renderCardIcon(selectedResultItem.iconType)}
                  </div>
                  <div>
                    <h4 className="text-[15px] font-extrabold text-white">
                      {contentPreset === 'luqma-ar'
                        ? selectedResultItem.titleAr
                        : contentPreset === 'luqma-en'
                        ? selectedResultItem.luqmaTitleEn
                        : selectedResultItem.titleEn}
                    </h4>
                    <span className="text-[12px] text-[#9EA3AE]">
                      {selectedResultItem.matchPct}% Match
                    </span>
                  </div>
                </div>
                <button
                  onClick={() => setSelectedResultItem(null)}
                  className="px-3 py-1.5 rounded-lg bg-[#32363E] text-[12px] font-bold text-white"
                >
                  {isRtl ? 'إغلاق' : 'Close'}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="min-h-screen bg-[#5F646D] text-white font-sans flex flex-col">
      {/* Top Studio Control Header */}
      <header className="bg-[#14161A]/95 border-b border-white/10 sticky top-0 z-40 px-4 py-3 backdrop-blur-md">
        <div className="max-w-7xl mx-auto flex flex-wrap items-center justify-between gap-3">
          <div className="flex items-center gap-2.5">
            <div className="w-3 h-3 rounded-full bg-[#F6720A]" />
            <span className="text-[13.5px] font-extrabold tracking-tight text-white">
              شاشات البحث لتطبيق لقمة (Luqma Search Screens — 100% Exact Match)
            </span>
          </div>

          <div className="flex items-center gap-2 flex-wrap">
            {/* View Mode Toggle */}
            <div className="inline-flex rounded-xl bg-[#22252C] p-1 border border-white/10">
              <button
                onClick={() => setViewMode('all-three')}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[12px] font-bold transition-colors ${
                  viewMode === 'all-three'
                    ? 'bg-[#F6720A] text-white'
                    : 'text-[#A0A5B1] hover:text-white'
                }`}
              >
                <Columns className="w-3.5 h-3.5" />
                <span>الشاشات الثلاث معاً (All 3 Screens)</span>
              </button>
              <button
                onClick={() => setViewMode('interactive')}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[12px] font-bold transition-colors ${
                  viewMode === 'interactive'
                    ? 'bg-[#F6720A] text-white'
                    : 'text-[#A0A5B1] hover:text-white'
                }`}
              >
                <Eye className="w-3.5 h-3.5" />
                <span>معاينة تفاعلية (Interactive State)</span>
              </button>
              <button
                onClick={() => setViewMode('specs')}
                className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-[12px] font-bold transition-colors ${
                  viewMode === 'specs'
                    ? 'bg-[#F6720A] text-white'
                    : 'text-[#A0A5B1] hover:text-white'
                }`}
              >
                <Layers className="w-3.5 h-3.5" />
                <span>المقاسات والألوان (Specs)</span>
              </button>
            </div>

            {/* Content / Language Preset Toggle */}
            <div className="inline-flex rounded-xl bg-[#22252C] p-1 border border-white/10">
              <button
                onClick={() => setContentPreset('exact')}
                className={`px-2.5 py-1.5 rounded-lg text-[11.5px] font-bold transition-colors ${
                  contentPreset === 'exact'
                    ? 'bg-white text-[#101114]'
                    : 'text-[#A0A5B1] hover:text-white'
                }`}
              >
                Exact Reference
              </button>
              <button
                onClick={() => setContentPreset('luqma-en')}
                className={`px-2.5 py-1.5 rounded-lg text-[11.5px] font-bold transition-colors ${
                  contentPreset === 'luqma-en'
                    ? 'bg-white text-[#101114]'
                    : 'text-[#A0A5B1] hover:text-white'
                }`}
              >
                Luqma (EN)
              </button>
              <button
                onClick={() => setContentPreset('luqma-ar')}
                className={`px-2.5 py-1.5 rounded-lg text-[11.5px] font-bold transition-colors ${
                  contentPreset === 'luqma-ar'
                    ? 'bg-white text-[#101114]'
                    : 'text-[#A0A5B1] hover:text-white'
                }`}
              >
                لقمة (عربي RTL)
              </button>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content Area */}
      <main className="flex-1 max-w-7xl w-full mx-auto px-4 py-8">
        {viewMode === 'all-three' && (
          <div className="space-y-6">
            <div className="flex flex-col xl:flex-row items-center justify-center gap-8">
              {/* Screen 1: Search Results */}
              <div className="flex flex-col items-center space-y-3">
                <span className="px-3.5 py-1 rounded-full bg-[#14161A]/90 border border-white/15 text-[12px] font-bold text-white shadow">
                  1. شاشة نتائج البحث (Search Results — 8 results found)
                </span>
                {renderSearchScreen('results', true)}
              </div>

              {/* Screen 2: Woops, Not Found */}
              <div className="flex flex-col items-center space-y-3">
                <span className="px-3.5 py-1 rounded-full bg-[#14161A]/90 border border-white/15 text-[12px] font-bold text-white shadow">
                  2. شاشة عدم وجود نتائج (Woops, Not Found 😢)
                </span>
                {renderSearchScreen('not-found', true)}
              </div>

              {/* Screen 3: Loading... */}
              <div className="flex flex-col items-center space-y-3">
                <span className="px-3.5 py-1 rounded-full bg-[#14161A]/90 border border-white/15 text-[12px] font-bold text-white shadow">
                  3. شاشة جاري التحميل (Loading...)
                </span>
                {renderSearchScreen('loading', true)}
              </div>
            </div>
          </div>
        )}

        {viewMode === 'interactive' && (
          <div className="flex flex-col items-center space-y-6">
            {/* State Switcher Pills */}
            <div className="inline-flex items-center gap-2 bg-[#14161A] p-1.5 rounded-2xl border border-white/15 shadow-lg">
              {[
                { id: 'results', label: '1. Search Results (8 found)' },
                { id: 'not-found', label: '2. Woops, Not Found 😢' },
                { id: 'loading', label: '3. Loading... (Animated)' }
              ].map((st) => (
                <button
                  key={st.id}
                  onClick={() => setActiveScreenState(st.id)}
                  className={`px-4 py-2 rounded-xl text-[12.5px] font-bold transition-all ${
                    activeScreenState === st.id
                      ? 'bg-[#F6720A] text-white shadow'
                      : 'text-[#A0A5B1] hover:text-white'
                  }`}
                >
                  {st.label}
                </button>
              ))}
            </div>

            {renderSearchScreen(activeScreenState, false)}
          </div>
        )}

        {viewMode === 'specs' && (
          <div className="max-w-4xl mx-auto bg-[#14161A] border border-white/15 rounded-3xl p-6 space-y-6 shadow-2xl">
            <h2 className="text-lg font-extrabold text-[#F6720A]">
              المواصفات الهندسية والألوان الدقيقة لشاشات البحث (Exact Search UI Tokens)
            </h2>

            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              {[
                { name: 'Header Orange (Results/Empty)', hex: '#F6720A' },
                { name: 'Header Orange (Loading)', hex: '#E67824' },
                { name: 'Search Input Box', hex: '#101114' },
                { name: 'Main Body Dark Bg', hex: '#0D0E11' },
                { name: 'Result Card Surface', hex: '#1D2026' },
                { name: 'Icon Squircle Surface', hex: '#32363E' },
                { name: 'Fitness Green Badge', hex: '#4E7D2B' },
                { name: 'Workout Blue Badge', hex: '#1D4ED8' },
                { name: 'Coaching Crimson Badge', hex: '#84262E' },
                { name: 'Fitness Slate Badge', hex: '#4B5262' },
                { name: 'Schedule Purple Badge', hex: '#6B21A8' },
                { name: 'Inactive Spinner Dot', hex: '#35383F' }
              ].map((c) => (
                <div
                  key={c.name}
                  className="bg-[#1D2026] border border-white/10 rounded-xl p-3 space-y-2"
                >
                  <div
                    className="w-full h-10 rounded-lg border border-white/15"
                    style={{ backgroundColor: c.hex }}
                  />
                  <div className="text-[11.5px] font-bold text-white">{c.name}</div>
                  <div className="text-[11px] font-mono text-[#F6720A]">{c.hex}</div>
                </div>
              ))}
            </div>
          </div>
        )}
      </main>
    </div>
  );
}