import json

file = r'C:\Github\ExchangeELK\dashboards\fortimail-dashboard.ndjson'

with open(file, 'r', encoding='utf-8') as f:
    lines = [l.rstrip('\n') for l in f if l.strip()]

metric_ids = {'fm-viz-total-count','fm-viz-inbound-count','fm-viz-blocked-count','fm-viz-spam-count','fm-viz-virus-count'}

new_panels = [
    {"panelIndex":"1",  "gridData":{"x":0,  "y":0,   "w":10,"h":7,  "i":"1"},  "embeddableConfig":{}, "panelRefName":"panel_1"},
    {"panelIndex":"2",  "gridData":{"x":10, "y":0,   "w":10,"h":7,  "i":"2"},  "embeddableConfig":{}, "panelRefName":"panel_2"},
    {"panelIndex":"3",  "gridData":{"x":20, "y":0,   "w":10,"h":7,  "i":"3"},  "embeddableConfig":{}, "panelRefName":"panel_3"},
    {"panelIndex":"4",  "gridData":{"x":30, "y":0,   "w":9, "h":7,  "i":"4"},  "embeddableConfig":{}, "panelRefName":"panel_4"},
    {"panelIndex":"5",  "gridData":{"x":39, "y":0,   "w":9, "h":7,  "i":"5"},  "embeddableConfig":{}, "panelRefName":"panel_5"},
    {"panelIndex":"6",  "gridData":{"x":0,  "y":7,   "w":48,"h":10, "i":"6"},  "embeddableConfig":{}, "panelRefName":"panel_6"},
    {"panelIndex":"7",  "gridData":{"x":0,  "y":17,  "w":48,"h":16, "i":"7"},  "embeddableConfig":{}, "panelRefName":"panel_7"},
    {"panelIndex":"8",  "gridData":{"x":0,  "y":33,  "w":12,"h":16, "i":"8"},  "embeddableConfig":{}, "panelRefName":"panel_8"},
    {"panelIndex":"9",  "gridData":{"x":12, "y":33,  "w":12,"h":16, "i":"9"},  "embeddableConfig":{}, "panelRefName":"panel_9"},
    {"panelIndex":"10", "gridData":{"x":24, "y":33,  "w":12,"h":16, "i":"10"}, "embeddableConfig":{}, "panelRefName":"panel_10"},
    {"panelIndex":"11", "gridData":{"x":36, "y":33,  "w":12,"h":16, "i":"11"}, "embeddableConfig":{}, "panelRefName":"panel_11"},
    {"panelIndex":"12", "gridData":{"x":0,  "y":49,  "w":16,"h":18, "i":"12"}, "embeddableConfig":{}, "panelRefName":"panel_12"},
    {"panelIndex":"13", "gridData":{"x":16, "y":49,  "w":16,"h":18, "i":"13"}, "embeddableConfig":{}, "panelRefName":"panel_13"},
    {"panelIndex":"14", "gridData":{"x":32, "y":49,  "w":16,"h":18, "i":"14"}, "embeddableConfig":{}, "panelRefName":"panel_14"},
    {"panelIndex":"15", "gridData":{"x":0,  "y":67,  "w":24,"h":18, "i":"15"}, "embeddableConfig":{}, "panelRefName":"panel_15"},
    {"panelIndex":"16", "gridData":{"x":24, "y":67,  "w":24,"h":18, "i":"16"}, "embeddableConfig":{}, "panelRefName":"panel_16"},
    {"panelIndex":"17", "gridData":{"x":0,  "y":85,  "w":48,"h":18, "i":"17"}, "embeddableConfig":{}, "panelRefName":"panel_17"},
    {"panelIndex":"18", "gridData":{"x":0,  "y":103, "w":48,"h":22, "i":"18"}, "embeddableConfig":{}, "panelRefName":"panel_18"}
]

out = []
for line in lines:
    obj = json.loads(line)
    oid = obj.get('id', '')

    # Fix metric font size
    if oid in metric_ids:
        vs = json.loads(obj['attributes']['visState'])
        vs['params']['metric']['style']['fontSize'] = 60
        obj['attributes']['visState'] = json.dumps(vs, separators=(',', ':'))
        print(f'Fixed fontSize: {oid}')

    # Fix traffic time chart: filters agg -> terms on log_type
    if oid == 'fm-viz-traffic-time':
        vs = json.loads(obj['attributes']['visState'])
        for agg in vs.get('aggs', []):
            if str(agg.get('id')) == '3':
                agg['type'] = 'terms'
                agg['params'] = {
                    'field': 'log_type',
                    'size': 6,
                    'order': 'desc',
                    'orderBy': '1',
                    'otherBucket': False,
                    'missingBucket': False
                }
                print('Fixed traffic chart agg id=3 (filters->terms)')
        obj['attributes']['visState'] = json.dumps(vs, separators=(',', ':'))

    # Fix dashboard panel layout
    if oid == 'fm-dashboard':
        obj['attributes']['panelsJSON'] = json.dumps(new_panels, separators=(',', ':'))
        print('Fixed dashboard panel layout')

    out.append(json.dumps(obj, separators=(',', ':')))

with open(file, 'w', encoding='utf-8', newline='\n') as f:
    f.write('\n'.join(out) + '\n')

print(f'Saved. Total lines: {len(out)}')
