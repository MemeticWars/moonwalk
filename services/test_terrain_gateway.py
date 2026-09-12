"""Contract tests with an analytic raster; no live GeoServer needed."""
import base64
import io
import json
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.request import urlopen
from urllib.error import HTTPError

import numpy as np
import tifffile

import terrain_gateway as gateway


CONFIG = {
    'geoserver_url': 'http://unused/geoserver', 'revision': 'test-v1', 'cache_mb': 1,
    'sectors': {'silesia': {'dem_layer': 'moon:dem', 'ortho_layer': '', 'crs': 'EPSG:100002',
                         'origin_easting_m': 1000, 'origin_northing_m': 2000,
                         'reference_elevation_m': 50, 'tile_bounds': [-4, -4, 4, 4]}}
}


def analytic_wcs(endpoint, params):
    assert params['service'] == 'WCS'
    left, bottom, right, top = map(float, params['bbox'].split(','))
    w, h = params['width'], params['height']
    xs = left + (np.arange(w) + 0.5) * (right - left) / w
    ys = top - (np.arange(h) + 0.5) * (top - bottom) / h
    values = (xs[None, :] * 0.25 + ys[:, None] * 0.125 + 50).astype('float32')
    buffer = io.BytesIO()
    tifffile.imwrite(buffer, values)
    return buffer.getvalue()


def heights(payload):
    data = json.loads(payload)
    return np.frombuffer(base64.b64decode(data['height_f32']), dtype='<f4').reshape(35, 35)


class ContractTests(unittest.TestCase):
    @patch.object(gateway, 'fetch', side_effect=analytic_wcs)
    def test_shared_edges_and_halo_including_negative_coordinates(self, _fetch):
        a = heights(gateway.make_tile(CONFIG, 'silesia', -1, 0))
        b = heights(gateway.make_tile(CONFIG, 'silesia', 0, 0))
        south = heights(gateway.make_tile(CONFIG, 'silesia', -1, 1))
        np.testing.assert_array_equal(a[:, -3:], b[:, :3])
        np.testing.assert_array_equal(a[-3:, :], south[:3, :])
        self.assertEqual(a[1, 1], (1000 - 64) * 0.25 + 2000 * 0.125)
        self.assertEqual(a[2, 1] - a[1, 1], -0.25)

    @patch.object(gateway, 'fetch', side_effect=analytic_wcs)
    def test_http_cache_and_bounds(self, fetch):
        with tempfile.TemporaryDirectory() as folder:
            server = gateway.Gateway(('127.0.0.1', 0), CONFIG, Path(folder))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                base = f'http://127.0.0.1:{server.server_port}'
                with urlopen(base + '/v1/test-v1/silesia/0/0.json') as result:
                    first = result.read()
                with urlopen(base + '/v1/test-v1/silesia/0/0.json') as result:
                    self.assertEqual(first, result.read())
                self.assertEqual(fetch.call_count, 1)
                for path in ['/v1/test-v1/silesia/99/0.json', '/v1/wrong/silesia/0/0.json', '/v1/test-v1/unknown/0/0.json']:
                    with self.assertRaises(HTTPError) as exc:
                        urlopen(base + path)
                    self.assertEqual(exc.exception.code, 404)
            finally:
                server.shutdown()
                server.server_close()
                thread.join()

    @patch.object(gateway, 'fetch')
    def test_nodata_rejected(self, fetch):
        buffer = io.BytesIO()
        tifffile.imwrite(buffer, np.full((35, 35), -32768, dtype='float32'))
        fetch.return_value = buffer.getvalue()
        with self.assertRaisesRegex(ValueError, 'NoData'):
            gateway.make_tile(CONFIG, 'silesia', 0, 0)

    @patch.object(gateway, 'fetch')
    def test_wrong_shape_rejected(self, fetch):
        buffer = io.BytesIO()
        tifffile.imwrite(buffer, np.zeros((20, 20), dtype='float32'))
        fetch.return_value = buffer.getvalue()
        with self.assertRaisesRegex(ValueError, 'Expected'):
            gateway.make_tile(CONFIG, 'silesia', 0, 0)


if __name__ == '__main__':
    unittest.main()
