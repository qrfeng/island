import QtQuick

// Shared response for geometry, selection and content. Behaviors retarget
// from their current value, so reversing a transition stays continuous.
NumberAnimation {
  property var theme: null
  property string pace: "standard"
  property string curve: "settle"
  // A call site that forgets `theme:` used to run at 240ms regardless of the
  // table or the user's speed; fall back to the settled defaults instead.
  duration: theme ? theme.motionDuration(pace) : Math.round(95 * 1.5)
  easing.type: Easing.BezierSpline
  easing.bezierCurve: theme ? theme.motionCurve(curve) : [0.16, 1, 0.3, 1, 1, 1]
}
