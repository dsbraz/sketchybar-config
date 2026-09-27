#!/bin/sh
case $(date +%u) in
  1) weekday=seg ;; 2) weekday=ter ;; 3) weekday=qua ;;
  4) weekday=qui ;; 5) weekday=sex ;; 6) weekday=sáb ;; 7) weekday=dom ;;
esac
case $(date +%m) in
  01) month=jan ;; 02) month=fev ;; 03) month=mar ;;
  04) month=abr ;; 05) month=mai ;; 06) month=jun ;;
  07) month=jul ;; 08) month=ago ;; 09) month=set ;;
  10) month=out ;; 11) month=nov ;; 12) month=dez ;;
esac
day=$(date +%d | sed 's/^0//')
sketchybar --set "$NAME" label="$weekday, $day de $month de $(date '+%Y  ·  %H:%M')"
