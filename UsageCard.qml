import QtQuick
import qs.Commons
import "Model.js" as Model

// BATTERY USAGE — the iOS Daily Usage card: the comparison sentence, the
// seven-day bars, the live marker, the hour-by-hour pack level and the
// Screen On / Screen Off totals.
//
// Tapping a bar selects that day: the card then shows that day's own curve,
// level and Screen On/Off totals, exactly as iOS opens a previous day, and a
// "Today" chip returns to the live view. A day the meter never saw renders as
// an empty grid with its date and an em dash, never as 0%.
//
// Pure view: the panel hands over the report produced by scripts/juice-usage
// and owns which day is selected; this file only formats and paints it.
Rectangle {
  id: card

  property var report: ({})
  property bool unavailable: false
  property color foreground: "#ffffff"
  property string fontFamily: ""
  property color accentColor: "#0A84FF"
  property color greenColor: "#30D158"
  property color yellowColor: "#FFD60A"
  property color redColor: "#FF453A"

  // "" is the live/today view; any other value is an ISO date in the report.
  property string selectedDate: ""

  signal daySelected(string date)

  readonly property var days: Array.isArray(report.daily) ? report.daily : []
  readonly property var hours: Array.isArray(report.hours) ? report.hours : []
  readonly property var today: report.today || ({})
  readonly property string clock: report.now ? (report.now.clock || "") : ""
  readonly property int topScale: Model.usageTopScale(days)

  readonly property var selectedDay: Model.usageDay(report, selectedDate)
  // A stale date (the report rolled over midnight) falls back to the live view.
  readonly property bool showingPast: selectedDate !== "" && selectedDay !== null && !selectedDay.today
  readonly property var shownHours: {
    if (showingPast && Array.isArray(selectedDay.hours)) return selectedDay.hours
    return hours
  }
  readonly property string sentence: {
    if (unavailable) return "Usage tracking needs python3 — install it to meter battery use"
    if (showingPast) return Model.usageDaySentence(selectedDay)
    return Model.usageSentence(report)
  }
  // One owner for the percentage: the section header summary reads the same
  // helper, so a closed and an open card can never print different numbers.
  readonly property string headerPercent: Model.usagePercentLabel(
    showingPast ? selectedDay : null, today)
  readonly property string headerDate: showingPast
    ? Model.formatUsageDate(selectedDay.date)
    : Model.formatUsageDate(today.date || "")
  // Screen time is only a fact for a day the sampler itself ran: a day
  // backfilled from UPower's level history has a curve but no screen totals.
  readonly property bool screenTotalsKnown: {
    if (!showingPast) return true
    if (!selectedDay || selectedDay.measured !== true) return false
    return (Number(selectedDay.screenOn) || 0) + (Number(selectedDay.screenOff) || 0) > 0
  }
  readonly property string screenOnText: screenTotalsKnown
    ? Model.formatSpan(showingPast ? selectedDay.screenOn : today.screenOn)
    : "—"
  readonly property string screenOffText: screenTotalsKnown
    ? Model.formatSpan(showingPast ? selectedDay.screenOff : today.screenOff)
    : "—"

  width: parent ? parent.width : 0
  radius: Style.cornerRadius > 0 ? Style.cornerRadius : 10
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.04)
  border.width: 1
  border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)
  implicitHeight: usageColumn.implicitHeight + Style.space(20)

  Column {
    id: usageColumn
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(10)
    spacing: Style.space(8)

    // The comparison line, exactly the iOS card's opening sentence.
    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: card.sentence
      color: card.foreground
      font.family: card.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      wrapMode: Text.WordWrap
      lineHeight: 1.15
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.1)
    }

    // The selected day's number sits above the chart at the right edge, with
    // its date under it — the way iOS labels the live bar. A past day also
    // carries the way back, so a tapped day is never a dead end.
    Item {
      width: parent.width
      implicitHeight: Math.max(headerColumn.implicitHeight, todayChip.height)

      Rectangle {
        id: todayChip
        visible: card.showingPast
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: todayChipText.implicitWidth + Style.space(16)
        height: Style.space(22)
        radius: height / 2
        color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.08)
        border.width: 1
        border.color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.12)

        Text {
          id: todayChipText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: "‹ Today"
          color: card.foreground
          font.family: card.fontFamily
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: card.daySelected("")
        }
      }

      Column {
        id: headerColumn
        anchors.right: parent.right
        spacing: 0

        Text {
          textFormat: Text.PlainText
          width: implicitWidth
          horizontalAlignment: Text.AlignRight
          text: card.headerPercent
          color: card.accentColor
          font.family: card.fontFamily
          font.pixelSize: Style.font.heading
          font.bold: true
        }

        Text {
          textFormat: Text.PlainText
          width: implicitWidth
          horizontalAlignment: Text.AlignRight
          text: card.headerDate
          color: card.foreground
          opacity: 0.6
          font.family: card.fontFamily
          font.pixelSize: Style.font.caption
        }

        // The day's measured discharge, when the meter priced one: the curve
        // says when, this says how much.
        Text {
          readonly property string energyText: card.showingPast && card.selectedDay
            ? Model.formatEnergyWh(card.selectedDay.energyWh) : ""
          textFormat: Text.PlainText
          width: implicitWidth
          horizontalAlignment: Text.AlignRight
          visible: energyText !== ""
          text: energyText
          color: card.foreground
          opacity: 0.5
          font.family: card.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    DailyChart {
      width: parent.width
      days: card.days
      topScale: card.topScale
    }

    Row {
      spacing: Style.space(10)

      Row {
        spacing: Style.space(4)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(6)
          height: width
          radius: width / 2
          color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.28)
        }

        Text {
          textFormat: Text.PlainText
          text: "All Day"
          color: card.foreground
          opacity: 0.7
          font.family: card.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        // The by-now split is a live-day distinction; a finished day has one
        // total, so its legend would describe a bar that is not drawn.
        visible: !card.showingPast
        spacing: Style.space(4)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(6)
          height: width
          radius: width / 2
          color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.55)
        }

        Text {
          textFormat: Text.PlainText
          text: "Daily by " + (card.clock === "" ? "now" : card.clock)
          color: card.foreground
          opacity: 0.7
          font.family: card.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    // The day's pack level hour by hour: green above half, yellow down to 20%,
    // red below, with a bolt on the hours it charged.
    LevelChart {
      width: parent.width
      hours: card.shownHours
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.1)
    }

    Row {
      width: parent.width
      spacing: Style.space(10)

      Column {
        width: (parent.width - Style.space(10)) / 2
        spacing: 1

        Text {
          textFormat: Text.PlainText
          text: "Screen On"
          color: card.foreground
          opacity: 0.6
          font.family: card.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          textFormat: Text.PlainText
          text: card.screenOnText
          color: card.foreground
          font.family: card.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }
      }

      Column {
        width: (parent.width - Style.space(10)) / 2
        spacing: 1

        Text {
          textFormat: Text.PlainText
          text: "Screen Off"
          color: card.foreground
          opacity: 0.6
          font.family: card.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          textFormat: Text.PlainText
          text: card.screenOffText
          color: card.foreground
          font.family: card.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }
      }
    }
  }

  // Gridlines and their right-edge labels, shared by both charts. Value labels
  // are derived from the chart's own scale so the 200% daily axis and the 100%
  // level axis print the same three rows without either restating the other.
  component ChartGrid: Item {
    id: grid

    property real maxValue: 200
    property real plotWidth: 0
    property real plotHeight: 0

    width: parent ? parent.width : 0
    height: plotHeight

    Repeater {
      model: [0, 1, 2]

      Item {
        required property int index
        readonly property real fraction: index / 2
        width: grid.width
        height: 1
        y: grid.plotHeight - grid.plotHeight * fraction

        Rectangle {
          width: grid.plotWidth
          height: 1
          color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.12)
        }

        Text {
          anchors.left: parent.right
          anchors.leftMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Math.round(grid.maxValue * fraction) + "%"
          color: card.foreground
          opacity: 0.5
          font.family: card.fontFamily
          font.pixelSize: Style.font.caption - 1
        }
      }
    }
  }

  // The seven-day bars: dim bar for the whole day, brighter bar for the portion
  // used by this clock time, today in iOS blue with the live marker.
  component DailyChart: Item {
    id: chart
    property var days: []
    property real topScale: 200

    implicitHeight: Style.space(124)

    readonly property real labelWidth: Style.space(34)
    readonly property real plotWidth: Math.max(0, width - labelWidth)
    readonly property real plotHeight: Style.space(82)
    readonly property real gap: Style.space(5)
    readonly property real barWidth: Math.max(2, (plotWidth - gap * 7) / 7)
    readonly property int todayIndex: {
      for (var i = 0; i < days.length; i++) if (days[i].today) return i
      return days.length - 1
    }

    ChartGrid {
      width: chart.width
      plotWidth: chart.plotWidth
      plotHeight: chart.plotHeight
      maxValue: chart.topScale
    }

    // The live marker first, so the bars paint over it where they overlap.
    Rectangle {
      visible: chart.days.length > 0
      x: chart.todayIndex * (chart.barWidth + chart.gap) + chart.barWidth / 2
      width: 1
      height: chart.plotHeight
      color: card.accentColor
      opacity: 0.8
    }

    Repeater {
      model: chart.days

      Item {
        required property var modelData
        required property int index

        x: index * (chart.barWidth + chart.gap)
        width: chart.barWidth
        height: chart.plotHeight

        readonly property real used: (modelData.used === null || modelData.used === undefined) ? 0 : modelData.used
        readonly property real byNow: (modelData.byNow === null || modelData.byNow === undefined) ? 0 : modelData.byNow

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          radius: Math.min(2, width / 2)
          height: parent.used > 0
            ? Math.max(2, Math.min(1, parent.used / chart.topScale) * chart.plotHeight)
            : 0
          color: modelData.today
            ? Qt.rgba(card.accentColor.r, card.accentColor.g, card.accentColor.b, 0.35)
            : Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.16)
        }

        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          radius: Math.min(2, width / 2)
          height: parent.byNow > 0
            ? Math.max(2, Math.min(1, parent.byNow / chart.topScale) * chart.plotHeight)
            : 0
          color: modelData.today
            ? card.accentColor
            : Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.38)
        }

        // A selected day keeps a ring around its bar, so the body below still
        // says which day it belongs to after the tap.
        Rectangle {
          visible: card.selectedDate === String(modelData.date)
          anchors.horizontalCenter: parent.horizontalCenter
          y: -Style.space(2)
          width: parent.width + Style.space(4)
          height: chart.plotHeight + Style.space(4)
          radius: 3
          color: "transparent"
          border.width: 1
          border.color: Qt.rgba(card.foreground.r, card.foreground.g, card.foreground.b, 0.45)
        }

        // The bars are barely 10 px wide; the tap target is the lane around
        // them, down to the weekday label. Tapping today returns to the live
        // view, so the same gesture both opens a day and comes back.
        MouseArea {
          x: -chart.gap / 2
          y: -Style.space(2)
          width: parent.width + chart.gap
          height: chart.plotHeight + Style.space(28)
          cursorShape: Qt.PointingHandCursor
          onClicked: card.daySelected(modelData.today ? "" : String(modelData.date))
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          y: chart.plotHeight + Style.space(4)
          textFormat: Text.PlainText
          text: modelData.label || ""
          color: modelData.today ? card.accentColor : card.foreground
          opacity: modelData.today ? 1 : 0.6
          font.family: card.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: modelData.today
        }

        // iOS dates the first bar; one date is enough to anchor the week.
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          y: chart.plotHeight + Style.space(16)
          visible: index === 0
          textFormat: Text.PlainText
          text: modelData.day + "/" + modelData.month
          color: card.foreground
          opacity: 0.5
          font.family: card.fontFamily
          font.pixelSize: Style.font.caption - 1
        }
      }
    }
  }

  // The day's pack level, hour by hour. Missing hours stay empty instead of
  // drawing a bar the meter never saw.
  component LevelChart: Item {
    id: chart
    property var hours: []

    implicitHeight: Style.space(96)

    readonly property real labelWidth: Style.space(34)
    readonly property real plotWidth: Math.max(0, width - labelWidth)
    readonly property real plotHeight: Style.space(66)
    readonly property real gap: Style.space(2)
    readonly property real barWidth: Math.max(2, (plotWidth - gap * 23) / 24)

    ChartGrid {
      width: chart.width
      plotWidth: chart.plotWidth
      plotHeight: chart.plotHeight
      maxValue: 100
    }

    Repeater {
      model: chart.hours

      Item {
        required property var modelData
        required property int index

        x: index * (chart.barWidth + chart.gap)
        width: chart.barWidth
        height: chart.plotHeight

        readonly property real level: modelData.level === null || modelData.level === undefined ? -1 : modelData.level

        Rectangle {
          visible: parent.level >= 0
          anchors.bottom: parent.bottom
          width: parent.width
          radius: Math.min(1.5, width / 2)
          height: parent.level >= 0 ? Math.max(2, parent.level / 100 * chart.plotHeight) : 0
          color: Model.usageLevelColor(parent.level, card.greenColor, card.yellowColor, card.redColor)
        }

        // The charging hours carry the same bolt iOS paints above the bar.
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: modelData.charging && parent.level >= 0
          y: chart.plotHeight - (parent.level / 100 * chart.plotHeight) - Style.space(12)
          textFormat: Text.PlainText
          text: "⚡"
          color: card.greenColor
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          y: chart.plotHeight + Style.space(4)
          textFormat: Text.PlainText
          text: Model.hourLabel(modelData.h)
          color: card.foreground
          opacity: 0.5
          font.family: card.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
