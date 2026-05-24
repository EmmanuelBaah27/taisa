// mobile/src/components/ui/GlowDevSheet.tsx
import { useEffect } from 'react';
import { View, Text, TouchableOpacity } from 'react-native';
import { GestureDetector, Gesture } from 'react-native-gesture-handler';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  runOnJS,
} from 'react-native-reanimated';
import type { GlowDevControls } from '../../hooks/useGlowDevControls';

const TRACK_WIDTH = 200;

// ─── DevSlider ───────────────────────────────────────────────────────────────

interface DevSliderProps {
  value: number;
  min: number;
  max: number;
  onChange: (v: number) => void;
}

function DevSlider({ value, min, max, onChange }: DevSliderProps) {
  const initialOffset = ((value - min) / (max - min)) * TRACK_WIDTH;
  const offsetX = useSharedValue(initialOffset);
  const startX = useSharedValue(initialOffset);

  const pan = Gesture.Pan()
    .onBegin(() => { startX.value = offsetX.value; })
    .onUpdate((e) => {
      const next = Math.max(0, Math.min(TRACK_WIDTH, startX.value + e.translationX));
      offsetX.value = next;
      const newVal = min + (next / TRACK_WIDTH) * (max - min);
      runOnJS(onChange)(parseFloat(newVal.toFixed(2)));
    });

  const fillStyle = useAnimatedStyle(() => ({ width: offsetX.value }));
  const thumbStyle = useAnimatedStyle(() => ({
    transform: [{ translateX: offsetX.value - 8 }],
  }));

  return (
    <GestureDetector gesture={pan}>
      <View style={{ width: TRACK_WIDTH, height: 32, justifyContent: 'center' }}>
        <View style={{ height: 3, backgroundColor: 'rgba(255,255,255,0.15)', borderRadius: 2, width: TRACK_WIDTH }}>
          <Animated.View style={[{ height: 3, backgroundColor: '#c6eb52', borderRadius: 2 }, fillStyle]} />
        </View>
        <Animated.View style={[{
          position: 'absolute',
          width: 16,
          height: 16,
          borderRadius: 8,
          backgroundColor: '#ffffff',
          top: 8,
          shadowColor: '#000',
          shadowOffset: { width: 0, height: 1 },
          shadowOpacity: 0.3,
          shadowRadius: 2,
        }, thumbStyle]} />
      </View>
    </GestureDetector>
  );
}

// ─── Segment ─────────────────────────────────────────────────────────────────

interface SegmentProps {
  options: (1 | 2 | 3)[];
  value: 1 | 2 | 3;
  onChange: (v: 1 | 2 | 3) => void;
}

function Segment({ options, value, onChange }: SegmentProps) {
  return (
    <View style={{ flexDirection: 'row', gap: 4 }}>
      {options.map((opt) => (
        <TouchableOpacity
          key={opt}
          onPress={() => onChange(opt)}
          style={{
            width: 36,
            height: 28,
            borderRadius: 6,
            backgroundColor: value === opt ? '#c6eb52' : 'rgba(255,255,255,0.1)',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <Text style={{ color: value === opt ? '#060707' : '#ffffff', fontSize: 13, fontWeight: '600' }}>
            {opt}
          </Text>
        </TouchableOpacity>
      ))}
    </View>
  );
}

// ─── Toggle ──────────────────────────────────────────────────────────────────

interface ToggleProps {
  value: boolean;
  onChange: (v: boolean) => void;
}

function Toggle({ value, onChange }: ToggleProps) {
  return (
    <View style={{ flexDirection: 'row', gap: 4 }}>
      {([false, true] as const).map((opt) => (
        <TouchableOpacity
          key={String(opt)}
          onPress={() => onChange(opt)}
          style={{
            paddingHorizontal: 14,
            height: 28,
            borderRadius: 6,
            backgroundColor: value === opt ? '#c6eb52' : 'rgba(255,255,255,0.1)',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <Text style={{ color: value === opt ? '#060707' : '#ffffff', fontSize: 12, fontWeight: '600' }}>
            {opt ? 'on' : 'off'}
          </Text>
        </TouchableOpacity>
      ))}
    </View>
  );
}

// ─── Row / Divider ────────────────────────────────────────────────────────────

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: 8 }}>
      <Text style={{ color: 'rgba(255,255,255,0.55)', fontSize: 12, width: 100 }}>{label}</Text>
      {children}
    </View>
  );
}

function Divider({ label }: { label: string }) {
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', marginVertical: 6 }}>
      <View style={{ flex: 1, height: 1, backgroundColor: 'rgba(255,255,255,0.08)' }} />
      <Text style={{ color: 'rgba(255,255,255,0.25)', fontSize: 10, paddingHorizontal: 8 }}>{label}</Text>
      <View style={{ flex: 1, height: 1, backgroundColor: 'rgba(255,255,255,0.08)' }} />
    </View>
  );
}

// ─── GlowDevSheet ─────────────────────────────────────────────────────────────

export interface GlowDevSheetProps {
  controls: GlowDevControls;
  visible: boolean;
  onDismiss: () => void;
}

export function GlowDevSheet({ controls, visible, onDismiss }: GlowDevSheetProps) {
  const {
    minAmplitude, maxAmplitude, ditherIntensity, colorCount,
    cubeEnabled, cubeSize,
    setMinAmplitude, setMaxAmplitude, setDitherIntensity, setColorCount,
    setCubeEnabled, setCubeSize,
  } = controls;

  const translateY = useSharedValue(-420);

  useEffect(() => {
    translateY.value = withSpring(visible ? 0 : -420, {
      damping: 22,
      stiffness: 220,
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible]);

  const sheetStyle = useAnimatedStyle(() => ({
    transform: [{ translateY: translateY.value }],
  }));

  return (
    <Animated.View
      style={[{
        position: 'absolute',
        top: 0,
        left: 0,
        right: 0,
        zIndex: 100,
        backgroundColor: 'rgba(8,8,12,0.94)',
        borderBottomLeftRadius: 18,
        borderBottomRightRadius: 18,
        paddingHorizontal: 20,
        paddingTop: 54,
        paddingBottom: 18,
      }, sheetStyle]}
      pointerEvents={visible ? 'auto' : 'none'}
    >
      <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 14 }}>
        <Text style={{ color: '#ffffff', fontSize: 11, fontWeight: '700', letterSpacing: 1.5, textTransform: 'uppercase', opacity: 0.7 }}>
          Glow Dev Controls
        </Text>
        <TouchableOpacity onPress={onDismiss} hitSlop={12}>
          <Text style={{ color: 'rgba(255,255,255,0.45)', fontSize: 18, lineHeight: 20 }}>✕</Text>
        </TouchableOpacity>
      </View>

      <Row label="Min amplitude">
        <DevSlider value={minAmplitude} min={0} max={1} onChange={setMinAmplitude} />
      </Row>
      <Row label="Max amplitude">
        <DevSlider value={maxAmplitude} min={0} max={1} onChange={setMaxAmplitude} />
      </Row>
      <Row label="Dither">
        <DevSlider value={ditherIntensity} min={0} max={1} onChange={setDitherIntensity} />
      </Row>
      <Row label="Colors">
        <Segment options={[1, 2, 3]} value={colorCount} onChange={setColorCount} />
      </Row>

      <Divider label="Cube Layer" />

      <Row label="Cube overlay">
        <Toggle value={cubeEnabled} onChange={setCubeEnabled} />
      </Row>
      <Row label="Cube size">
        <DevSlider value={cubeSize} min={4} max={64} onChange={(v) => setCubeSize(Math.round(v))} />
      </Row>
    </Animated.View>
  );
}
