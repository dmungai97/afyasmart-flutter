import { useState } from 'react';
import {
  View, Text, TouchableOpacity, StyleSheet,
  ScrollView, TextInput, ActivityIndicator, Alert,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { requestSymptomsAnalysis } from '@/src/services/symptoms.service';
import { useAuthStore } from '@/src/store/authStore';
import { isSubscriptionActive } from '@/src/services/subscription.model';
import { useDiagnosisStore } from '@/src/store/diagnosisStore';

const TEAL   = '#0B6E6E';
const GREEN  = '#16A34A';
const RED    = '#DC2626';
const ORANGE = '#D97706';
const PURPLE = '#7C3AED';

type Step = 'entry' | 'symptoms' | 'details' | 'questions' | 'processing' | 'results' | 'history';
type Condition = { name: string; likelihood: 'High' | 'Medium' | 'Low'; percent: number; color: string };
type Medication = { name: string; desc: string; icon: string };

const POPULAR_SYMPTOMS = ['Fever', 'Headache', 'Cough', 'Stomach pain', 'Body pain', 'Sore throat', 'Nausea', 'Diarrhea', 'Fatigue', 'Chest pain'];

const SMART_QUESTIONS = [
  { id: 'fever',    question: 'Do you have a fever?',           sub: 'Temperature above 37.5°C' },
  { id: 'duration', question: 'How long have symptoms lasted?', sub: 'Please choose one option', options: ['< 1 day', '1–3 days', '4–7 days', '1 week+'] },
  { id: 'travel',   question: 'Have you travelled recently?',   sub: 'In the last 2 weeks' },
  { id: 'contact',  question: 'Contacted someone sick?',        sub: 'Close contact with ill person' },
  { id: 'meds',     question: 'Are you on any medication?',     sub: 'Prescription or OTC drugs' },
];

const DURATION_OPTIONS = ['Today', '1–3 days', '4–7 days', '1 week+'];
const SEVERITY_LABELS  = ['Mild', 'Moderate', 'Severe'];

export function SymptomsScreen() {
  const router = useRouter();
  const user = useAuthStore(state => state.user);
  const isSubscribed = isSubscriptionActive(user);
  const setPendingDiagnosis = useDiagnosisStore(s => s.setPendingDiagnosis);

  const [step, setStep]               = useState<Step>('entry');
  const [selectedSymptoms, setSelectedSymptoms] = useState<string[]>([]);
  const [symptomInput, setSymptomInput]         = useState('');
  const [age, setAge]                 = useState(25);
  const [gender, setGender]           = useState<string | null>(null);
  const [duration, setDuration]       = useState<string | null>(null);
  const [severity, setSeverity]       = useState(1);
  const [questionIdx, setQuestionIdx] = useState(0);
  const [answers, setAnswers]         = useState<Record<string, string>>({});
  const [results, setResults]         = useState<Condition[]>([]);
  const [medications, setMedications] = useState<Medication[]>([]);
  const [selfCare, setSelfCare]       = useState<string[]>([]);
  const [urgency, setUrgency]         = useState({ level: 'Medium', desc: 'Your symptoms may need medical attention.' });
  const [processingStep, setProcessingStep] = useState(0);

  const HISTORY = [
    { id: 1, symptoms: 'Fever, Headache',    date: '2 days ago',    viewed: true  },
    { id: 2, symptoms: 'Stomach pain',       date: '1 week ago',    viewed: true  },
    { id: 3, symptoms: 'Cough, Sore throat', date: '2 weeks ago',   viewed: true  },
    { id: 4, symptoms: 'Body pain, Fever',   date: '1 month ago',   viewed: false },
  ];

  const toggleSymptom = (s: string) => {
    setSelectedSymptoms(prev =>
      prev.includes(s) ? prev.filter(x => x !== s) : [...prev, s]
    );
  };

  const addCustomSymptom = () => {
    const trimmed = symptomInput.trim();
    if (trimmed && !selectedSymptoms.includes(trimmed)) {
      setSelectedSymptoms(prev => [...prev, trimmed]);
    }
    setSymptomInput('');
  };

  const startProcessing = async () => {
    setStep('processing');
    setProcessingStep(0);

    // Visual loading steps
    const timer1 = setTimeout(() => setProcessingStep(1), 1000);
    const timer2 = setTimeout(() => setProcessingStep(2), 2000);

    try {
      const data = await requestSymptomsAnalysis({
        symptoms: selectedSymptoms,
        age,
        gender: gender || 'male',
        duration: duration || '1–3 days',
        severity: SEVERITY_LABELS[severity] || 'Moderate',
        answers,
      });

      clearTimeout(timer1);
      clearTimeout(timer2);
      setProcessingStep(3);

      setResults(data.conditions);
      setMedications(data.medications);
      setSelfCare(data.self_care);
      setUrgency({
        level: data.urgency,
        desc: data.urgency_desc,
      });

      // Format and store in the diagnosis store so it persists if they upgrade/subscribe later
      const formattedDiagnosis = {
        symptoms: selectedSymptoms.join(', '),
        summary: data.urgency_desc,
        urgency: data.urgency,
        conditions: data.conditions.map(c => ({
          name: c.name,
          probability: c.percent,
          level: c.likelihood,
          color: c.color,
        })),
        medications: data.medications.map(m => ({
          name: m.name,
          note: m.desc,
        })),
        preparedAt: new Date().toISOString(),
      };
      setPendingDiagnosis(formattedDiagnosis);

      setTimeout(() => {
        setStep('results');
      }, 500);

    } catch (err: any) {
      clearTimeout(timer1);
      clearTimeout(timer2);
      setStep('entry');
      Alert.alert(
        "Analysis Limited",
        err?.message ?? "An error occurred while analyzing symptoms. Please try again."
      );
    }
  };

  if (step === 'entry') {
    return (
      <View style={styles.root}>
        <View style={styles.entryHeader}>
          <TouchableOpacity onPress={() => router.back()} style={styles.entryBackBtn}>
            <Ionicons name="arrow-back" size={20} color="#fff" />
          </TouchableOpacity>
          <TouchableOpacity style={styles.infoBtn}>
            <Ionicons name="information-circle-outline" size={22} color="#fff" />
          </TouchableOpacity>
        </View>

        <ScrollView contentContainerStyle={styles.entryContent} showsVerticalScrollIndicator={false}>
          <View style={styles.illustration}>
            <View style={styles.illustrationCircle}>
              <Text style={styles.illustrationEmoji}>🩺</Text>
            </View>
            <View style={styles.illustrationBadge}>
              <Ionicons name="shield-checkmark" size={14} color={GREEN} />
              <Text style={styles.illustrationBadgeText}>AI-Powered</Text>
            </View>
          </View>

          <Text style={styles.entryTitle}>Symptom Checker</Text>
          <Text style={styles.entrySub}>Find possible causes and{'\n'}what to do next</Text>

          <View style={styles.featurePills}>
            {[
              { icon: 'checkmark-circle', text: 'Answer simple questions', color: GREEN  },
              { icon: 'bulb-outline',     text: 'Get possible conditions',  color: ORANGE },
              { icon: 'navigate-outline', text: 'Know what to do next',     color: TEAL   },
            ].map((f, i) => (
              <View key={i} style={styles.featurePill}>
                <Ionicons name={f.icon as any} size={16} color={f.color} />
                <Text style={styles.featurePillText}>{f.text}</Text>
              </View>
            ))}
          </View>

          <TouchableOpacity
            style={styles.startBtn}
            onPress={() => setStep('symptoms')}
            activeOpacity={0.85}
          >
            <Text style={styles.startBtnText}>Start Check</Text>
            <Ionicons name="arrow-forward" size={18} color="#fff" />
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.historyBtn}
            onPress={() => setStep('history')}
          >
            <Text style={styles.historyBtnText}>Continue previous check</Text>
          </TouchableOpacity>
        </ScrollView>
      </View>
    );
  }

  if (step === 'history') {
    return (
      <View style={styles.root}>
        <View style={styles.stepHeader}>
          <TouchableOpacity onPress={() => setStep('entry')} style={styles.headerBack}>
            <Ionicons name="arrow-back" size={20} color="#fff" />
          </TouchableOpacity>
          <Text style={styles.stepHeaderTitle}>Check History</Text>
          <View style={{ width: 36 }} />
        </View>
        <ScrollView contentContainerStyle={{ padding: 20, gap: 12 }}>
          <Text style={styles.historySubtitle}>Your past symptom checks</Text>
          {HISTORY.map(h => (
            <TouchableOpacity key={h.id} style={styles.historyCard}>
              <View style={[styles.historyIcon, { backgroundColor: h.viewed ? '#EFF6FF' : '#F3EEFF' }]}>
                <Ionicons name="document-text-outline" size={20} color={h.viewed ? TEAL : PURPLE} />
              </View>
              <View style={styles.historyInfo}>
                <Text style={styles.historySymptoms}>{h.symptoms}</Text>
                <Text style={styles.historyDate}>{h.date}</Text>
              </View>
              <View style={[styles.viewedBadge, h.viewed && styles.viewedBadgeActive]}>
                <Text style={[styles.viewedBadgeText, h.viewed && styles.viewedBadgeTextActive]}>
                  {h.viewed ? 'Viewed' : 'New'}
                </Text>
              </View>
              <Ionicons name="chevron-forward" size={16} color="#ccc" />
            </TouchableOpacity>
          ))}
          <View style={styles.historyTip}>
            <Ionicons name="shield-checkmark-outline" size={16} color={TEAL} />
            <Text style={styles.historyTipText}>
              You can always revisit your results and follow up with a doctor.
            </Text>
          </View>
        </ScrollView>
      </View>
    );
  }

  if (step === 'symptoms') {
    const filtered = POPULAR_SYMPTOMS.filter(s =>
      s.toLowerCase().includes(symptomInput.toLowerCase())
    );

    return (
      <View style={styles.root}>
        <View style={styles.stepHeader}>
          <TouchableOpacity onPress={() => setStep('entry')} style={styles.headerBack}>
            <Ionicons name="arrow-back" size={20} color="#fff" />
          </TouchableOpacity>
          <Text style={styles.stepHeaderTitle}>What are your symptoms?</Text>
          <View style={{ width: 36 }} />
        </View>
        <Text style={styles.stepHeaderSub2}>Type or select your symptoms</Text>

        <ScrollView
          contentContainerStyle={styles.symptomsContent}
          showsVerticalScrollIndicator={false}
          keyboardShouldPersistTaps="handled"
        >
          <View style={styles.symptomSearch}>
            <Ionicons name="search-outline" size={18} color="#aaa" />
            <TextInput
              style={styles.symptomSearchInput}
              placeholder="Search symptoms..."
              placeholderTextColor="#9AA7A7"
              selectionColor={TEAL}
              cursorColor={TEAL}
              value={symptomInput}
              onChangeText={setSymptomInput}
              onSubmitEditing={addCustomSymptom}
              returnKeyType="done"
            />
            {symptomInput.length > 0 && (
              <TouchableOpacity onPress={addCustomSymptom}>
                <Ionicons name="add-circle" size={20} color={TEAL} />
              </TouchableOpacity>
            )}
          </View>

          <Text style={styles.sectionLabel}>Popular symptoms</Text>
          <View style={styles.symptomChips}>
            {filtered.map(s => (
              <TouchableOpacity
                key={s}
                style={[styles.symptomChip, selectedSymptoms.includes(s) && styles.symptomChipActive]}
                onPress={() => toggleSymptom(s)}
              >
                <Text style={[styles.symptomChipText, selectedSymptoms.includes(s) && styles.symptomChipTextActive]}>
                  {s}
                </Text>
              </TouchableOpacity>
            ))}
          </View>

          {selectedSymptoms.length > 0 && (
            <>
              <Text style={styles.sectionLabel}>Your symptoms</Text>
              <View style={styles.symptomChips}>
                {selectedSymptoms.map(s => (
                  <TouchableOpacity
                    key={s}
                    style={styles.selectedChip}
                    onPress={() => toggleSymptom(s)}
                  >
                    <Text style={styles.selectedChipText}>{s}</Text>
                    <Ionicons name="close" size={14} color="#fff" />
                  </TouchableOpacity>
                ))}
              </View>
            </>
          )}
        </ScrollView>

        <View style={styles.bottomBtn}>
          <TouchableOpacity
            style={[styles.nextBtn, selectedSymptoms.length === 0 && styles.nextBtnDisabled]}
            onPress={() => selectedSymptoms.length > 0 && setStep('details')}
            disabled={selectedSymptoms.length === 0}
          >
            <Text style={styles.nextBtnText}>Next</Text>
            <Ionicons name="arrow-forward" size={18} color="#fff" />
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  if (step === 'details') {
    return (
      <View style={styles.root}>
        <View style={styles.stepHeader}>
          <TouchableOpacity onPress={() => setStep('symptoms')} style={styles.headerBack}>
            <Ionicons name="arrow-back" size={20} color="#fff" />
          </TouchableOpacity>
          <Text style={styles.stepHeaderTitle}>Some details about you</Text>
          <View style={{ width: 36 }} />
        </View>
        <Text style={styles.stepHeaderSub2}>This helps us give accurate results</Text>

        <ScrollView contentContainerStyle={styles.detailsContent} showsVerticalScrollIndicator={false}>
          <View style={styles.detailCard}>
            <View style={styles.detailCardHeader}>
              <Text style={styles.detailLabel}>Age</Text>
              <Text style={styles.detailValue}>{age} years</Text>
            </View>
            <View style={styles.sliderTrack}>
              <View style={[styles.sliderFill, { width: `${(age / 100) * 100}%` }]} />
              <TouchableOpacity
                style={[styles.sliderThumb, { left: `${(age / 100) * 100}%` as any }]}
              />
            </View>
            <View style={styles.sliderRange}>
              <Text style={styles.sliderRangeText}>1</Text>
              <View style={styles.ageButtons}>
                <TouchableOpacity style={styles.ageBtn} onPress={() => setAge(Math.max(1, age - 1))}>
                  <Ionicons name="remove" size={16} color={TEAL} />
                </TouchableOpacity>
                <Text style={styles.ageBtnValue}>{age}</Text>
                <TouchableOpacity style={styles.ageBtn} onPress={() => setAge(Math.min(100, age + 1))}>
                  <Ionicons name="add" size={16} color={TEAL} />
                </TouchableOpacity>
              </View>
              <Text style={styles.sliderRangeText}>100</Text>
            </View>
          </View>

          <View style={styles.detailCard}>
            <Text style={styles.detailLabel}>Gender</Text>
            <View style={styles.genderRow}>
              {[
                { id: 'male',   label: 'Male',          icon: '♂' },
                { id: 'female', label: 'Female',        icon: '♀' },
                { id: 'other',  label: 'Prefer not to say', icon: '○' },
              ].map(g => (
                <TouchableOpacity
                  key={g.id}
                  style={[styles.genderBtn, gender === g.id && styles.genderBtnActive]}
                  onPress={() => setGender(g.id)}
                >
                  <Text style={styles.genderIcon}>{g.icon}</Text>
                  <Text style={[styles.genderLabel, gender === g.id && styles.genderLabelActive]}>
                    {g.label}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>

          <View style={styles.detailCard}>
            <Text style={styles.detailLabel}>Duration of symptoms</Text>
            <View style={styles.durationRow}>
              {DURATION_OPTIONS.map(d => (
                <TouchableOpacity
                  key={d}
                  style={[styles.durationBtn, duration === d && styles.durationBtnActive]}
                  onPress={() => setDuration(d)}
                >
                  <Text style={[styles.durationText, duration === d && styles.durationTextActive]}>
                    {d}
                  </Text>
                </TouchableOpacity>
              ))}
            </View>
          </View>

          <View style={styles.detailCard}>
            <View style={styles.detailCardHeader}>
              <Text style={styles.detailLabel}>Severity</Text>
              <Text style={styles.detailValue2}>How bad is it?</Text>
            </View>
            <View style={styles.severityRow}>
              {SEVERITY_LABELS.map((s, i) => (
                <TouchableOpacity
                  key={s}
                  style={[styles.severityBtn, severity === i && styles.severityBtnActive]}
                  onPress={() => setSeverity(i)}
                >
                  <Text style={[styles.severityText, severity === i && styles.severityTextActive]}>{s}</Text>
                </TouchableOpacity>
              ))}
            </View>
            <View style={styles.severityBar}>
              <View style={[
                styles.severityBarFill,
                { width: `${((severity + 1) / 3) * 100}%`,
                  backgroundColor: severity === 0 ? GREEN : severity === 1 ? ORANGE : RED }
              ]} />
            </View>
            <View style={styles.severityRange}>
              <Text style={styles.severityRangeText}>Mild</Text>
              <Text style={styles.severityRangeText}>Severe</Text>
            </View>
          </View>
        </ScrollView>

        <View style={styles.bottomBtn}>
          <TouchableOpacity
            style={styles.nextBtn}
            onPress={() => { setQuestionIdx(0); setStep('questions'); }}
          >
            <Text style={styles.nextBtnText}>Continue</Text>
            <Ionicons name="arrow-forward" size={18} color="#fff" />
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  if (step === 'questions') {
    const q       = SMART_QUESTIONS[questionIdx];
    const total   = SMART_QUESTIONS.length;
    const progress = ((questionIdx) / total) * 100;
    const isLast  = questionIdx === total - 1;
    const currentAnswer = answers[q.id];

    const handleAnswer = (val: string) => {
      setAnswers(prev => ({ ...prev, [q.id]: val }));
    };

    const handleNext = () => {
      if (isLast) {
        startProcessing();
      } else {
        setQuestionIdx(i => i + 1);
      }
    };

    return (
      <View style={styles.root}>
        <View style={styles.stepHeader}>
          <TouchableOpacity
            onPress={() => questionIdx === 0 ? setStep('details') : setQuestionIdx(i => i - 1)}
            style={styles.headerBack}
          >
            <Ionicons name="arrow-back" size={20} color="#fff" />
          </TouchableOpacity>
          <Text style={styles.stepProgress}>Step {questionIdx + 1} of {total}</Text>
          <View style={{ width: 36 }} />
        </View>

        <View style={styles.progressTrack}>
          <View style={[styles.progressFill, { width: `${progress + (100 / total)}%` }]} />
        </View>

        <ScrollView contentContainerStyle={styles.questionContent} showsVerticalScrollIndicator={false}>
          <View style={styles.questionIconWrap}>
            <Text style={styles.questionIconEmoji}>❓</Text>
          </View>

          <Text style={styles.questionText}>{q.question}</Text>
          <Text style={styles.questionSub}>{q.sub}</Text>

          {q.options ? (
            <View style={styles.optionsCol}>
              {q.options.map(opt => (
                <TouchableOpacity
                  key={opt}
                  style={[styles.optionBtn, currentAnswer === opt && styles.optionBtnActive]}
                  onPress={() => handleAnswer(opt)}
                >
                  <Text style={[styles.optionText, currentAnswer === opt && styles.optionTextActive]}>
                    {opt}
                  </Text>
                  {currentAnswer === opt ? (
                    <Ionicons name="checkmark-circle" size={22} color={TEAL} />
                  ) : (
                    <View style={styles.optionRadio} />
                  )}
                </TouchableOpacity>
              ))}
            </View>
          ) : (
            <View style={styles.optionsCol}>
              {['Yes', 'No'].map(opt => (
                <TouchableOpacity
                  key={opt}
                  style={[styles.optionBtn, currentAnswer === opt && styles.optionBtnActive]}
                  onPress={() => handleAnswer(opt)}
                >
                  <Text style={[styles.optionText, currentAnswer === opt && styles.optionTextActive]}>
                    {opt}
                  </Text>
                  {currentAnswer === opt ? (
                    <Ionicons name="checkmark-circle" size={22} color={TEAL} />
                  ) : (
                    <View style={styles.optionRadio} />
                  )}
                </TouchableOpacity>
              ))}
            </View>
          )}

          <View style={styles.tipCard}>
            <Text style={styles.tipIcon}>💡</Text>
            <View style={styles.tipContent}>
              <Text style={styles.tipTitle}>Tip</Text>
              <Text style={styles.tipText}>
                Answering accurately helps us find the right possible causes.
              </Text>
            </View>
          </View>
        </ScrollView>

        <View style={styles.bottomBtn}>
          <TouchableOpacity
            style={[styles.nextBtn, !currentAnswer && styles.nextBtnDisabled]}
            onPress={handleNext}
            disabled={!currentAnswer}
          >
            <Text style={styles.nextBtnText}>{isLast ? 'Analyze Symptoms' : 'Next'}</Text>
            <Ionicons name={isLast ? 'analytics-outline' : 'arrow-forward'} size={18} color="#fff" />
          </TouchableOpacity>
        </View>
      </View>
    );
  }

  if (step === 'processing') {
    const steps = ['Checking medical data...', 'Comparing conditions...', 'Preparing results...'];
    return (
      <View style={styles.root}>
        <View style={styles.processingContent}>
          <View style={styles.processingCircle}>
            <View style={styles.processingInner}>
              <Ionicons name="clipboard" size={48} color={TEAL} />
            </View>
          </View>

          <Text style={styles.processingTitle}>Analyzing your symptoms...</Text>

          <View style={styles.processingSteps}>
            {steps.map((s, i) => (
              <View key={i} style={styles.processingStep}>
                {processingStep > i ? (
                  <Ionicons name="checkmark-circle" size={20} color={GREEN} />
                ) : processingStep === i ? (
                  <ActivityIndicator size="small" color={TEAL} />
                ) : (
                  <View style={styles.processingDot} />
                )}
                <Text style={[
                  styles.processingStepText,
                  processingStep > i && styles.processingStepDone,
                  processingStep === i && styles.processingStepActive,
                ]}>
                  {s}
                </Text>
              </View>
            ))}
          </View>

          <View style={styles.secureNote}>
            <Ionicons name="lock-closed-outline" size={14} color="#888" />
            <Text style={styles.secureNoteText}>Your data is private and secure</Text>
          </View>
        </View>
      </View>
    );
  }

  if (step === 'results') {
    return (
      <View style={styles.root}>
        <View style={styles.stepHeader}>
          <TouchableOpacity onPress={() => setStep('entry')} style={styles.headerBack}>
            <Ionicons name="home-outline" size={20} color="#fff" />
          </TouchableOpacity>
          <Text style={styles.stepHeaderTitle}>Your Results</Text>
          <TouchableOpacity onPress={() => setStep('history')} style={styles.headerBack}>
            <Ionicons name="time-outline" size={20} color="#fff" />
          </TouchableOpacity>
        </View>

        <ScrollView contentContainerStyle={styles.resultsContent} showsVerticalScrollIndicator={false}>
          <Text style={styles.resultsTitle}>Here are your results</Text>
          <Text style={styles.resultsSub}>These are possible causes, not a diagnosis.</Text>

          <View style={styles.conditionsCard}>
            <View style={styles.conditionsHeader}>
              <Text style={styles.conditionsTitle}>Possible conditions</Text>
              <Ionicons name="information-circle-outline" size={16} color="#888" />
            </View>

            {isSubscribed ? (
              results.map((cond, i) => (
                <View key={i} style={[styles.conditionRow, i > 0 && { borderTopWidth: 0.5, borderTopColor: '#F3F4F6' }]}>
                  <View style={[styles.conditionDot, { backgroundColor: cond.color ?? RED }]} />
                  <View style={styles.conditionInfo}>
                    <Text style={styles.conditionName}>{cond.name}</Text>
                    <Text style={styles.conditionLikelihood}>{cond.likelihood} likelihood</Text>
                  </View>
                  <Text style={[styles.conditionPercent, { color: cond.color ?? RED }]}>
                    {cond.percent}%
                  </Text>
                </View>
              ))
            ) : (
              <>
                {results[0] && (
                  <View style={styles.conditionRow}>
                    <View style={[styles.conditionDot, { backgroundColor: results[0].color ?? RED }]} />
                    <View style={styles.conditionInfo}>
                      <Text style={styles.conditionName}>{results[0].name}</Text>
                      <Text style={styles.conditionLikelihood}>{results[0].likelihood} likelihood</Text>
                    </View>
                    <Text style={[styles.conditionPercent, { color: results[0].color ?? RED }]}>
                      {results[0].percent}%
                    </Text>
                  </View>
                )}

                {[1, 2].map((i) => (
                  <View key={i} style={styles.conditionRowLocked}>
                    <View style={styles.conditionDotLocked} />
                    <View style={styles.conditionInfoLocked}>
                      <View style={styles.lockedBar} />
                      <View style={[styles.lockedBar, { width: 80 }]} />
                    </View>
                    <Ionicons name="lock-closed" size={18} color="#ccc" />
                  </View>
                ))}

                <TouchableOpacity
                  style={styles.unlockCta}
                  onPress={() => router.push('/(tabs)/subscription' as any)}
                  activeOpacity={0.85}
                >
                  <Ionicons name="lock-open-outline" size={16} color="#fff" />
                  <Text style={styles.unlockCtaText}>Unlock Full Results</Text>
                </TouchableOpacity>

                <View style={styles.unlockTeaser}>
                  {[
                    'Detailed condition analysis',
                    'Recommended medication',
                    'Nearby doctors & pharmacies',
                    'AI follow-up chat',
                  ].map((t, i) => (
                    <View key={i} style={styles.teaserRow}>
                      <Ionicons name="checkmark-circle" size={14} color={GREEN} />
                      <Text style={styles.teaserText}>{t}</Text>
                    </View>
                  ))}
                </View>
              </>
            )}
          </View>

          <View style={styles.actionCard}>
            <View style={styles.actionHeader}>
              <Text style={styles.actionTitle}>What you should do</Text>
              <Ionicons name="information-circle-outline" size={16} color="#888" />
            </View>
            <Text style={styles.actionSub}>Based on your symptoms</Text>
            <View style={styles.urgentBanner}>
              <Text style={styles.urgentText}>
                {urgency.level === 'High' ? 'See a doctor as soon as possible' : urgency.level === 'Medium' ? 'Monitor symptoms closely' : 'General care recommended'}
              </Text>
              <Text style={styles.urgentDesc}>{urgency.desc}</Text>
              <View style={[styles.urgentPill, urgency.level === 'High' ? { backgroundColor: RED } : urgency.level === 'Medium' ? { backgroundColor: ORANGE } : { backgroundColor: TEAL }]}>
                <Text style={styles.urgentPillText}>{urgency.level} Priority</Text>
              </View>
            </View>

            <Text style={styles.selfCareTitle}>Self-care tips</Text>
            {selfCare.map((tip, i) => (
              <View key={i} style={styles.selfCareTip}>
                <Ionicons name="checkmark-circle" size={16} color={GREEN} />
                <Text style={styles.selfCareTipText}>{tip}</Text>
              </View>
            ))}
          </View>

          <View style={styles.medsCard}>
            <View style={styles.medsHeader}>
              <Text style={styles.medsTitle}>Suggested medication</Text>
              <Ionicons name="information-circle-outline" size={16} color="#888" />
            </View>
            <Text style={styles.medsSub}>Commonly used for these symptoms</Text>
            
            {isSubscribed ? (
              medications.map((m, i) => (
                <View key={i} style={styles.medRow}>
                  <Text style={styles.medIcon}>{m.icon || '💊'}</Text>
                  <View style={styles.medInfo}>
                    <Text style={styles.medName}>{m.name}</Text>
                    <Text style={styles.medDesc}>{m.desc}</Text>
                  </View>
                </View>
              ))
            ) : (
              <View style={styles.lockedSectionPlaceholder}>
                <Ionicons name="lock-closed" size={24} color={TEAL} style={{ marginBottom: 6 }} />
                <Text style={styles.lockedSectionTitle}>Suggested Medication Locked</Text>
                <Text style={styles.lockedSectionText}>Subscribe to premium to view recommended treatments and dosages.</Text>
                <TouchableOpacity
                  style={styles.lockedSectionBtn}
                  onPress={() => router.push('/(tabs)/subscription' as any)}
                >
                  <Text style={styles.lockedSectionBtnText}>Unlock with Premium</Text>
                </TouchableOpacity>
              </View>
            )}

            {isSubscribed && (
              <TouchableOpacity style={styles.viewAllMeds}>
                <Text style={styles.viewAllMedsText}>View all medications</Text>
              </TouchableOpacity>
            )}
          </View>

          <View style={styles.nearbyCard}>
            <Text style={styles.nearbyTitle}>Need help nearby?</Text>
            <Text style={styles.nearbySub}>Find healthcare services near you</Text>
            
            {isSubscribed ? (
              <>
                {[
                  { label: 'Nearby Pharmacies', desc: 'Find medicines near you',        icon: 'medkit-outline'   },
                  { label: 'Nearby Doctors',    desc: 'Book a consultation',            icon: 'people-outline'   },
                  { label: 'Nearby Hospitals',  desc: 'Emergency care centers',         icon: 'business-outline' },
                ].map((n, i) => (
                  <TouchableOpacity key={i} style={styles.nearbyRow}>
                    <View style={styles.nearbyIcon}>
                      <Ionicons name={n.icon as any} size={20} color={TEAL} />
                    </View>
                    <View style={styles.nearbyInfo}>
                      <Text style={styles.nearbyLabel}>{n.label}</Text>
                      <Text style={styles.nearbyDesc}>{n.desc}</Text>
                    </View>
                    <Ionicons name="chevron-forward" size={16} color="#ccc" />
                  </TouchableOpacity>
                ))}
                <TouchableOpacity style={styles.findNearMeBtn}>
                  <Ionicons name="location" size={16} color="#fff" />
                  <Text style={styles.findNearMeText}>Find Near Me</Text>
                </TouchableOpacity>
              </>
            ) : (
              <View style={styles.lockedSectionPlaceholder}>
                <Ionicons name="lock-closed" size={24} color={TEAL} style={{ marginBottom: 6 }} />
                <Text style={styles.lockedSectionTitle}>Nearby Services Locked</Text>
                <Text style={styles.lockedSectionText}>Locate pharmacies, doctors, and clinics in your area with a Premium plan.</Text>
                <TouchableOpacity
                  style={styles.lockedSectionBtn}
                  onPress={() => router.push('/(tabs)/subscription' as any)}
                >
                  <Text style={styles.lockedSectionBtnText}>Unlock with Premium</Text>
                </TouchableOpacity>
              </View>
            )}
          </View>

          <View style={styles.continueCare}>
            <View style={{ flex: 1 }}>
              <Text style={styles.continueCareTitle}>Continue care</Text>
              <Text style={styles.continueCareSub}>Chat with our AI Health Assistant for more guidance.</Text>
            </View>
            <TouchableOpacity 
              style={styles.chatNowBtn} 
              onPress={() => {
                if (!isSubscribed) {
                  router.push('/(tabs)/subscription' as any);
                } else {
                  router.push('/(tabs)/chat' as any);
                }
              }}
            >
              <Ionicons name={isSubscribed ? "chatbubble-ellipses" : "lock-closed"} size={16} color="#fff" />
              <Text style={styles.chatNowText}>{isSubscribed ? "Chat Now" : "Unlock Chat"}</Text>
            </TouchableOpacity>
          </View>
        </ScrollView>
      </View>
    );
  }

  return null;
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#F5F7FA' },
  entryHeader: {
    backgroundColor: TEAL,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingTop: 52,
    paddingHorizontal: 20,
    paddingBottom: 12,
  },
  entryBackBtn: {
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.15)',
    alignItems: 'center', justifyContent: 'center',
  },
  infoBtn: {
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.15)',
    alignItems: 'center', justifyContent: 'center',
  },
  entryContent: { padding: 24, alignItems: 'center', paddingBottom: 40 },
  illustration: { marginVertical: 20, alignItems: 'center' },
  illustrationCircle: {
    width: 120, height: 120, borderRadius: 60,
    backgroundColor: 'rgba(11,110,110,0.08)',
    alignItems: 'center', justifyContent: 'center',
  },
  illustrationEmoji:  { fontSize: 56 },
  illustrationBadge:  {
    flexDirection: 'row', alignItems: 'center', gap: 4,
    backgroundColor: '#E8F5E9',
    paddingHorizontal: 10, paddingVertical: 4,
    borderRadius: 20, marginTop: -12,
  },
  illustrationBadgeText: { fontSize: 11, color: GREEN, fontWeight: '700' },
  entryTitle: { fontSize: 28, fontWeight: '800', color: '#1a1a1a', marginBottom: 8, textAlign: 'center' },
  entrySub:   { fontSize: 15, color: '#888', textAlign: 'center', lineHeight: 22, marginBottom: 28 },
  featurePills: { width: '100%', gap: 10, marginBottom: 32 },
  featurePill:  { flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: '#fff', borderRadius: 12, padding: 12, borderWidth: 0.5, borderColor: '#eee' },
  featurePillText: { fontSize: 14, color: '#444', fontWeight: '500' },
  startBtn: {
    backgroundColor: TEAL, borderRadius: 14,
    paddingVertical: 15, paddingHorizontal: 32,
    flexDirection: 'row', alignItems: 'center', gap: 8,
    width: '100%', justifyContent: 'center', marginBottom: 12,
  },
  startBtnText: { color: '#fff', fontSize: 16, fontWeight: '800' },
  historyBtn:     { paddingVertical: 12 },
  historyBtnText: { color: '#888', fontSize: 14, fontWeight: '500' },
  stepHeader: {
    backgroundColor: TEAL,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingTop: 52,
    paddingHorizontal: 20,
    paddingBottom: 12,
  },
  headerBack: {
    width: 36, height: 36, borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.15)',
    alignItems: 'center', justifyContent: 'center',
  },
  stepHeaderTitle: { color: '#fff', fontSize: 16, fontWeight: '700', flex: 1, textAlign: 'center' },
  stepHeaderSub2:  { backgroundColor: TEAL, color: 'rgba(255,255,255,0.7)', fontSize: 12, textAlign: 'center', paddingBottom: 14, paddingHorizontal: 20 },
  stepProgress:    { color: '#fff', fontSize: 14, fontWeight: '600', flex: 1, textAlign: 'center' },
  progressTrack: { height: 4, backgroundColor: 'rgba(11,110,110,0.15)' },
  progressFill:  { height: 4, backgroundColor: TEAL, borderRadius: 2 },
  symptomsContent: { padding: 20, paddingBottom: 100 },
  symptomSearch: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    backgroundColor: '#F4F8F8', borderRadius: 14,
    paddingHorizontal: 16, minHeight: 50,
    borderWidth: 1.5, borderColor: '#DCE3E3',
    marginBottom: 20,
  },
  symptomSearchInput: {
    flex: 1, fontSize: 15, color: '#12201F',
    paddingVertical: 12,
  },
  sectionLabel:       { fontSize: 14, fontWeight: '700', color: '#1a1a1a', marginBottom: 12 },
  symptomChips:       { flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginBottom: 20 },
  symptomChip: {
    paddingHorizontal: 14, paddingVertical: 8,
    borderRadius: 20, borderWidth: 1, borderColor: '#E5E7EB',
    backgroundColor: '#fff',
  },
  symptomChipActive:     { backgroundColor: 'rgba(11,110,110,0.08)', borderColor: TEAL },
  symptomChipText:       { fontSize: 13, color: '#555', fontWeight: '500' },
  symptomChipTextActive: { color: TEAL, fontWeight: '700' },
  selectedChip: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    backgroundColor: TEAL, paddingHorizontal: 12, paddingVertical: 7,
    borderRadius: 20,
  },
  selectedChipText: { color: '#fff', fontSize: 13, fontWeight: '600' },
  detailsContent: { padding: 20, paddingBottom: 100, gap: 14 },
  detailCard: {
    backgroundColor: '#fff', borderRadius: 16,
    padding: 16, borderWidth: 0.5, borderColor: '#F0F0F0',
  },
  detailCardHeader: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 },
  detailLabel:  { fontSize: 14, fontWeight: '700', color: '#1a1a1a', marginBottom: 12 },
  detailValue:  { fontSize: 14, fontWeight: '700', color: TEAL },
  detailValue2: { fontSize: 12, color: '#888' },
  sliderTrack: { height: 6, backgroundColor: '#E5E7EB', borderRadius: 3, marginBottom: 12, position: 'relative' },
  sliderFill:  { height: 6, backgroundColor: TEAL, borderRadius: 3 },
  sliderThumb: { position: 'absolute', top: -7, width: 20, height: 20, borderRadius: 10, backgroundColor: TEAL, marginLeft: -10, shadowColor: TEAL, shadowOpacity: 0.3, shadowRadius: 4, elevation: 4 },
  sliderRange: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  sliderRangeText: { fontSize: 12, color: '#888' },
  ageButtons: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  ageBtn: {
    width: 32, height: 32, borderRadius: 8,
    backgroundColor: 'rgba(11,110,110,0.08)',
    alignItems: 'center', justifyContent: 'center',
  },
  ageBtnValue: { fontSize: 16, fontWeight: '700', color: '#1a1a1a', minWidth: 30, textAlign: 'center' },
  genderRow: { flexDirection: 'row', gap: 8 },
  genderBtn: {
    flex: 1, alignItems: 'center', paddingVertical: 12,
    borderRadius: 12, borderWidth: 1.5, borderColor: '#E5E7EB',
    backgroundColor: '#F9FAFB', gap: 4,
  },
  genderBtnActive: { borderColor: TEAL, backgroundColor: 'rgba(11,110,110,0.06)' },
  genderIcon:  { fontSize: 18 },
  genderLabel: { fontSize: 12, color: '#555', fontWeight: '500', textAlign: 'center' },
  genderLabelActive: { color: TEAL, fontWeight: '700' },
  durationRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  durationBtn: {
    paddingHorizontal: 14, paddingVertical: 9,
    borderRadius: 10, borderWidth: 1.5, borderColor: '#E5E7EB',
    backgroundColor: '#F9FAFB',
  },
  durationBtnActive: { borderColor: TEAL, backgroundColor: 'rgba(11,110,110,0.08)' },
  durationText:       { fontSize: 13, color: '#555', fontWeight: '500' },
  durationTextActive: { color: TEAL, fontWeight: '700' },
  severityRow: { flexDirection: 'row', gap: 8, marginBottom: 12 },
  severityBtn: {
    flex: 1, paddingVertical: 9, borderRadius: 10,
    alignItems: 'center', borderWidth: 1.5, borderColor: '#E5E7EB',
    backgroundColor: '#F9FAFB',
  },
  severityBtnActive: { borderColor: TEAL, backgroundColor: 'rgba(11,110,110,0.08)' },
  severityText:       { fontSize: 13, color: '#555', fontWeight: '500' },
  severityTextActive: { color: TEAL, fontWeight: '700' },
  severityBar:     { height: 6, backgroundColor: '#E5E7EB', borderRadius: 3, marginBottom: 6 },
  severityBarFill: { height: 6, borderRadius: 3 },
  severityRange:   { flexDirection: 'row', justifyContent: 'space-between' },
  severityRangeText: { fontSize: 11, color: '#aaa' },
  bottomBtn: {
    position: 'absolute', bottom: 55, left: 0, right: 0,
    padding: 20, backgroundColor: '#F5F7FA',
    borderTopWidth: 0.5, borderTopColor: '#E5E7EB',
  },
  nextBtn: {
    backgroundColor: TEAL, borderRadius: 14,
    paddingVertical: 15, flexDirection: 'row',
    alignItems: 'center', justifyContent: 'center', gap: 8,
  },
  nextBtnDisabled: { opacity: 0.4 },
  nextBtnText:     { color: '#fff', fontSize: 16, fontWeight: '800' },
  questionContent: { padding: 24, alignItems: 'center', paddingBottom: 120, gap: 16 },
  questionIconWrap: {
    width: 72, height: 72, borderRadius: 36,
    backgroundColor: 'rgba(124,58,237,0.1)',
    alignItems: 'center', justifyContent: 'center',
    marginBottom: 8,
  },
  questionIconEmoji: { fontSize: 32 },
  questionText: { fontSize: 22, fontWeight: '800', color: '#1a1a1a', textAlign: 'center' },
  questionSub:  { fontSize: 14, color: '#888', textAlign: 'center', marginBottom: 8 },
  optionsCol: { width: '100%', gap: 10 },
  optionBtn: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    backgroundColor: '#fff', borderRadius: 14,
    padding: 16, borderWidth: 1.5, borderColor: '#E5E7EB',
  },
  optionBtnActive: { borderColor: TEAL, backgroundColor: 'rgba(11,110,110,0.05)' },
  optionText:       { fontSize: 15, color: '#444', fontWeight: '500' },
  optionTextActive: { color: TEAL, fontWeight: '700' },
  optionRadio: {
    width: 22, height: 22, borderRadius: 11,
    borderWidth: 2, borderColor: '#D1D5DB',
  },
  tipCard: {
    flexDirection: 'row', gap: 10, alignItems: 'flex-start',
    backgroundColor: '#FFFBEB', borderRadius: 14,
    padding: 14, width: '100%',
    borderWidth: 0.5, borderColor: '#FDE68A',
  },
  tipIcon:    { fontSize: 18 },
  tipContent: { flex: 1 },
  tipTitle:   { fontSize: 13, fontWeight: '700', color: '#92400E', marginBottom: 4 },
  tipText:    { fontSize: 12, color: '#92400E', lineHeight: 18 },
  processingContent: {
    flex: 1, alignItems: 'center', justifyContent: 'center',
    padding: 32, gap: 24,
  },
  processingCircle: {
    width: 140, height: 140, borderRadius: 70,
    borderWidth: 3, borderColor: 'rgba(11,110,110,0.2)',
    alignItems: 'center', justifyContent: 'center',
  },
  processingInner: {
    width: 100, height: 100, borderRadius: 50,
    backgroundColor: 'rgba(11,110,110,0.08)',
    alignItems: 'center', justifyContent: 'center',
  },
  processingTitle: { fontSize: 20, fontWeight: '700', color: '#1a1a1a', textAlign: 'center' },
  processingSteps: { width: '100%', gap: 12 },
  processingStep:  { flexDirection: 'row', alignItems: 'center', gap: 12, backgroundColor: '#fff', borderRadius: 12, padding: 14 },
  processingDot:   { width: 20, height: 20, borderRadius: 10, backgroundColor: '#E5E7EB' },
  processingStepText:   { fontSize: 14, color: '#888' },
  processingStepActive: { color: TEAL, fontWeight: '600' },
  processingStepDone:   { color: GREEN, fontWeight: '600' },
  secureNote: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  secureNoteText: { fontSize: 12, color: '#888' },
  resultsContent: { padding: 16, paddingBottom: 40, gap: 14 },
  resultsTitle:   { fontSize: 20, fontWeight: '800', color: '#1a1a1a' },
  resultsSub:     { fontSize: 13, color: '#888', marginBottom: 4 },
  conditionsCard: {
    backgroundColor: '#fff', borderRadius: 16,
    padding: 16, borderWidth: 0.5, borderColor: '#F0F0F0',
  },
  conditionsHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 14 },
  conditionsTitle:  { fontSize: 14, fontWeight: '700', color: '#1a1a1a' },
  conditionRow:     { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 10, borderTopWidth: 0.5, borderTopColor: '#F3F4F6' },
  conditionDot:     { width: 10, height: 10, borderRadius: 5 },
  conditionInfo:    { flex: 1 },
  conditionName:    { fontSize: 14, fontWeight: '700', color: '#1a1a1a' },
  conditionLikelihood: { fontSize: 12, color: '#888' },
  conditionPercent:    { fontSize: 18, fontWeight: '800' },
  conditionDisclaimer: { fontSize: 11, color: '#aaa', marginTop: 12, lineHeight: 16 },
  actionCard: {
    backgroundColor: '#fff', borderRadius: 16,
    padding: 16, borderWidth: 0.5, borderColor: '#F0F0F0',
  },
  actionHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 2 },
  actionTitle:  { fontSize: 14, fontWeight: '700', color: '#1a1a1a' },
  actionSub:    { fontSize: 12, color: '#888', marginBottom: 12 },
  urgentBanner: {
    backgroundColor: '#FFF0F0', borderRadius: 12,
    padding: 14, marginBottom: 14,
    borderWidth: 0.5, borderColor: '#FECACA',
  },
  urgentText: { fontSize: 15, fontWeight: '800', color: RED, marginBottom: 4 },
  urgentDesc: { fontSize: 12, color: '#666', marginBottom: 10 },
  urgentPill: { backgroundColor: RED, borderRadius: 8, paddingHorizontal: 12, paddingVertical: 4, alignSelf: 'flex-start' },
  urgentPillText: { color: '#fff', fontSize: 12, fontWeight: '700' },
  selfCareTitle:   { fontSize: 13, fontWeight: '700', color: '#1a1a1a', marginBottom: 8 },
  selfCareTip:     { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 6 },
  selfCareTipText: { fontSize: 13, color: '#444', flex: 1 },
  medsCard: {
    backgroundColor: '#fff', borderRadius: 16,
    padding: 16, borderWidth: 0.5, borderColor: '#F0F0F0',
  },
  medsHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 2 },
  medsTitle:  { fontSize: 14, fontWeight: '700', color: '#1a1a1a' },
  medsSub:    { fontSize: 12, color: '#888', marginBottom: 12 },
  medRow:     { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 10, borderTopWidth: 0.5, borderTopColor: '#F3F4F6' },
  medIcon:    { fontSize: 28 },
  medInfo:    { flex: 1 },
  medName:    { fontSize: 14, fontWeight: '700', color: '#1a1a1a' },
  medDesc:    { fontSize: 12, color: '#888' },
  viewAllMeds: { borderWidth: 1, borderColor: '#E5E7EB', borderRadius: 10, paddingVertical: 11, alignItems: 'center', marginTop: 12 },
  viewAllMedsText: { fontSize: 13, color: '#555', fontWeight: '600' },
  nearbyCard: {
    backgroundColor: '#fff', borderRadius: 16,
    padding: 16, borderWidth: 0.5, borderColor: '#F0F0F0',
  },
  nearbyTitle: { fontSize: 14, fontWeight: '700', color: '#1a1a1a', marginBottom: 2 },
  nearbySub:   { fontSize: 12, color: '#888', marginBottom: 12 },
  nearbyRow:   { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 10, borderTopWidth: 0.5, borderTopColor: '#F3F4F6' },
  nearbyIcon:  {
    width: 38, height: 38, borderRadius: 10,
    backgroundColor: 'rgba(11,110,110,0.08)',
    alignItems: 'center', justifyContent: 'center',
  },
  nearbyInfo:  { flex: 1 },
  nearbyLabel: { fontSize: 13, fontWeight: '700', color: '#1a1a1a' },
  nearbyDesc:  { fontSize: 12, color: '#888' },
  findNearMeBtn: {
    backgroundColor: TEAL, borderRadius: 12,
    paddingVertical: 13, flexDirection: 'row',
    alignItems: 'center', justifyContent: 'center',
    gap: 8, marginTop: 12,
  },
  findNearMeText: { color: '#fff', fontSize: 14, fontWeight: '700' },
  continueCare: {
    backgroundColor: TEAL, borderRadius: 16,
    padding: 16, flexDirection: 'row',
    alignItems: 'center', justifyContent: 'space-between',
    gap: 12,
  },
  continueCareTitle: { fontSize: 14, fontWeight: '700', color: '#fff', marginBottom: 4 },
  continueCareSub:   { fontSize: 12, color: 'rgba(255,255,255,0.75)', flex: 1, lineHeight: 18 },
  chatNowBtn: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    backgroundColor: 'rgba(255,255,255,0.2)',
    paddingHorizontal: 14, paddingVertical: 10,
    borderRadius: 10,
  },
  chatNowText: { color: '#fff', fontWeight: '700', fontSize: 13 },
  historySubtitle: { fontSize: 13, color: '#888', marginBottom: 4 },
  historyCard: {
    backgroundColor: '#fff', borderRadius: 14,
    padding: 14, flexDirection: 'row',
    alignItems: 'center', gap: 12,
    borderWidth: 0.5, borderColor: '#F0F0F0',
  },
  historyIcon:     { width: 40, height: 40, borderRadius: 10, alignItems: 'center', justifyContent: 'center' },
  historyInfo:     { flex: 1 },
  historySymptoms: { fontSize: 14, fontWeight: '700', color: '#1a1a1a' },
  historyDate:     { fontSize: 12, color: '#888', marginTop: 2 },
  viewedBadge:     { paddingHorizontal: 8, paddingVertical: 4, borderRadius: 8, backgroundColor: '#F3F4F6' },
  viewedBadgeActive: { backgroundColor: '#E8F5E9' },
  viewedBadgeText:   { fontSize: 11, color: '#888', fontWeight: '600' },
  viewedBadgeTextActive: { color: GREEN },
  historyTip: {
    flexDirection: 'row', gap: 10, alignItems: 'flex-start',
    backgroundColor: '#E6F4F4', borderRadius: 14,
    padding: 14, borderWidth: 0.5, borderColor: 'rgba(11,110,110,0.2)',
  },
  historyTipText: { fontSize: 13, color: TEAL, flex: 1, lineHeight: 20 },
  conditionRowLocked: {
    flexDirection: 'row', alignItems: 'center',
    gap: 10, paddingVertical: 12,
    borderTopWidth: 0.5, borderTopColor: '#F3F4F6',
  },
  conditionDotLocked: {
    width: 10, height: 10, borderRadius: 5,
    backgroundColor: '#E5E7EB',
  },
  conditionInfoLocked: { flex: 1, gap: 6 },
  lockedBar: {
    height: 10, width: 120,
    backgroundColor: '#F3F4F6',
    borderRadius: 5,
  },
  unlockCta: {
    backgroundColor: TEAL,
    borderRadius: 12, paddingVertical: 13,
    flexDirection: 'row', alignItems: 'center',
    justifyContent: 'center', gap: 8, marginTop: 16,
  },
  unlockCtaText: { color: '#fff', fontSize: 15, fontWeight: '800' },
  unlockTeaser: { marginTop: 14, gap: 8 },
  teaserRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  teaserText: { fontSize: 13, color: '#555' },
  lockedSectionPlaceholder: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 20,
    paddingHorizontal: 16,
    backgroundColor: '#F9FAFB',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#E5E7EB',
    borderStyle: 'dashed',
    marginTop: 8,
  },
  lockedSectionTitle: {
    fontSize: 15,
    fontWeight: '800',
    color: '#1a1a1a',
    marginBottom: 4,
    textAlign: 'center',
  },
  lockedSectionText: {
    fontSize: 12,
    color: '#666',
    textAlign: 'center',
    lineHeight: 18,
    marginBottom: 14,
  },
  lockedSectionBtn: {
    backgroundColor: TEAL,
    borderRadius: 10,
    paddingVertical: 9,
    paddingHorizontal: 18,
  },
  lockedSectionBtnText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '700',
  },
});
